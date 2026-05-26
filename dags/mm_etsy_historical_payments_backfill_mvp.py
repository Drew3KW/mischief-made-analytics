from __future__ import annotations

import os
import subprocess
from datetime import UTC, datetime

from airflow import DAG
from airflow.decorators import task
from google.cloud import bigquery

DAG_ID = "mm_etsy_historical_payments_backfill_mvp"

PROJECT_ID = "mischief-made-analytics"
DATASET = "raw_load"

STATE_TABLE = "etsy_historical_payment_backfill_batches"
RECEIPTS_TABLE = "etsy_receipts_api_latest"
LATEST_PAYMENTS_TABLE = "etsy_receipt_payments_api_latest"
PAYMENT_CANDIDATE_TABLE = "etsy_receipt_payments_api_payment_backfill_candidate"
SKIPPED_RECEIPTS_TABLE = "etsy_receipt_payments_api_payment_backfill_skipped_receipts"

SCRIPT_PATH = "/opt/airflow/scripts/etsy_payments_backfill.py"

DEFAULT_ARGS = {
    "owner": "airflow",
    "retries": 0,
}


def table_id(table_name: str) -> str:
    return f"{PROJECT_ID}.{DATASET}.{table_name}"


def run_query(client: bigquery.Client, query: str) -> list[bigquery.table.Row]:
    job = client.query(query)
    return list(job.result())


def get_next_available_batch(client: bigquery.Client) -> dict[str, str] | None:
    query = f"""
    SELECT
        batch_id,
        batch_sequence,
        batch_receipt_count,
        batch_status
    FROM `{table_id(STATE_TABLE)}`
    WHERE batch_status IN ('PENDING', 'RATE_LIMIT')
    ORDER BY batch_sequence
    LIMIT 1
    """

    rows = run_query(client, query)

    if not rows:
        return None

    row = rows[0]

    return {
        "batch_id": row["batch_id"],
        "batch_sequence": str(row["batch_sequence"]),
        "batch_receipt_count": str(row["batch_receipt_count"]),
        "batch_status": row["batch_status"],
    }



def mark_batch_running(client: bigquery.Client, batch: dict[str, str]) -> None:
    query = f"""
    UPDATE `{table_id(STATE_TABLE)}`
    SET
        batch_status = 'RUNNING',
        started_at = CURRENT_TIMESTAMP(),
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP()
    WHERE batch_id = @batch_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("batch_id", "STRING", batch["batch_id"]),
        ]
    )

    client.query(query, job_config=job_config).result()


def mark_batch_rate_limited(
    client: bigquery.Client,
    batch: dict[str, str],
    error_message: str,
) -> None:
    query = f"""
    UPDATE `{table_id(STATE_TABLE)}`
    SET
        batch_status = 'RATE_LIMIT',
        error_message = @error_message,
        updated_at = CURRENT_TIMESTAMP()
    WHERE batch_id = @batch_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("batch_id", "STRING", batch["batch_id"]),
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
        ]
    )

    client.query(query, job_config=job_config).result()


def mark_batch_failed(
    client: bigquery.Client,
    batch: dict[str, str],
    error_message: str,
) -> None:
    query = f"""
    UPDATE `{table_id(STATE_TABLE)}`
    SET
        batch_status = 'FAILED',
        error_message = @error_message,
        updated_at = CURRENT_TIMESTAMP()
    WHERE batch_id = @batch_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("batch_id", "STRING", batch["batch_id"]),
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
        ]
    )

    client.query(query, job_config=job_config).result()


def get_batch_counts(
    client: bigquery.Client,
    batch: dict[str, str],
) -> dict[str, int]:
    query = f"""
    WITH selected_batch AS (
        SELECT
            batch_id,
            batch_start_position,
            batch_end_position
        FROM `{table_id(STATE_TABLE)}`
        WHERE batch_id = @batch_id
    ),

    existing_latest_payment_receipts AS (
        SELECT DISTINCT
            receipt_id
        FROM `{table_id(LATEST_PAYMENTS_TABLE)}`
        WHERE receipt_id IS NOT NULL
    ),

    receipt_universe AS (
        SELECT
            receipts.receipt_id,
            DATE(
                TIMESTAMP_SECONDS(
                    COALESCE(receipts.created_timestamp, receipts.create_timestamp)
                )
            ) AS receipt_created_date
        FROM `{table_id(RECEIPTS_TABLE)}` AS receipts
        LEFT JOIN existing_latest_payment_receipts AS latest_payments
            ON receipts.receipt_id = latest_payments.receipt_id
        WHERE receipts.receipt_id IS NOT NULL
          AND latest_payments.receipt_id IS NULL
          AND COALESCE(receipts.created_timestamp, receipts.create_timestamp)
              IS NOT NULL
    ),

    numbered_receipts AS (
        SELECT
            receipt_id,
            ROW_NUMBER() OVER (
                ORDER BY receipt_created_date, receipt_id
            ) AS receipt_position
        FROM receipt_universe
    ),

    batch_receipts AS (
        SELECT
            numbered_receipts.receipt_id
        FROM numbered_receipts
        CROSS JOIN selected_batch
        WHERE numbered_receipts.receipt_position
            BETWEEN selected_batch.batch_start_position
            AND selected_batch.batch_end_position
    ),

    payment_counts AS (
        SELECT
            COUNT(*) AS payment_row_count
        FROM `{table_id(PAYMENT_CANDIDATE_TABLE)}` AS payments
        INNER JOIN batch_receipts
            ON payments.receipt_id = batch_receipts.receipt_id
    ),

    skipped_counts AS (
        SELECT
            COUNT(DISTINCT IF(skip_reason = 'HTTP_404', receipt_id, NULL))
                AS skipped_404_count,
            COUNT(
                DISTINCT IF(
                    skip_reason = 'EMPTY_PAYMENT_RESPONSE',
                    receipt_id,
                    NULL
                )
            ) AS zero_payment_response_count
        FROM `{table_id(SKIPPED_RECEIPTS_TABLE)}`
        WHERE batch_id = @batch_id
    )

    SELECT
        payment_counts.payment_row_count,
        skipped_counts.skipped_404_count,
        skipped_counts.zero_payment_response_count
    FROM payment_counts
    CROSS JOIN skipped_counts
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("batch_id", "STRING", batch["batch_id"]),
        ]
    )

    rows = list(client.query(query, job_config=job_config).result())
    counts = rows[0]

    return {
        "payment_row_count": counts["payment_row_count"],
        "skipped_404_count": counts["skipped_404_count"],
        "zero_payment_response_count": counts["zero_payment_response_count"],
    }


def mark_batch_complete(
    client: bigquery.Client,
    batch: dict[str, str],
    counts: dict[str, int],
) -> None:
    query = f"""
    UPDATE `{table_id(STATE_TABLE)}`
    SET
        batch_status = 'COMPLETE',
        completed_at = CURRENT_TIMESTAMP(),
        payment_row_count = @payment_row_count,
        skipped_404_count = @skipped_404_count,
        zero_payment_response_count = @zero_payment_response_count,
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP()
    WHERE batch_id = @batch_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("batch_id", "STRING", batch["batch_id"]),
            bigquery.ScalarQueryParameter(
                "payment_row_count",
                "INT64",
                counts["payment_row_count"],
            ),
            bigquery.ScalarQueryParameter(
                "skipped_404_count",
                "INT64",
                counts["skipped_404_count"],
            ),
            bigquery.ScalarQueryParameter(
                "zero_payment_response_count",
                "INT64",
                counts["zero_payment_response_count"],
            ),
        ]
    )

    client.query(query, job_config=job_config).result()


def run_payment_backfill_script(batch: dict[str, str]) -> tuple[int, str]:
    command = [
        "python",
        SCRIPT_PATH,
        "--batch-id",
        batch["batch_id"],
    ]

    print("Running Etsy payment backfill command:")
    print(" ".join(command))

    env = os.environ.copy()
    env["GOOGLE_APPLICATION_CREDENTIALS"] = "/opt/airflow/keys/gcp-sa.json"

    result = subprocess.run(
        command,
        env=env,
        text=True,
        capture_output=True,
    )

    combined_output = result.stdout + result.stderr

    print("STDOUT:")
    print(result.stdout)

    print("STDERR:")
    print(result.stderr)

    return result.returncode, combined_output


def is_rate_limit_error(return_code: int, output: str) -> bool:
    return return_code == 2 and (
        "HTTP 429" in output
        or "Too Many Requests" in output
        or "Exceeded daily rate limit" in output
        or "Rate limit reached" in output
    )


with DAG(
    dag_id=DAG_ID,
    default_args=DEFAULT_ARGS,
    description=(
        "Process Etsy historical receipt payment backfill batches until "
        "rate limit or completion."
    ),
    start_date=datetime(2026, 5, 22, 0, 0, tzinfo=UTC),
    schedule="30 20 * * *",
    catchup=False,
    tags=["mischief-made", "etsy", "payments", "backfill", "mvp"],
) as dag:

    @task
    def process_batches_until_stopped() -> None:
        client = bigquery.Client(project=PROJECT_ID)

        completed_batches = 0

        while True:
            batch = get_next_available_batch(client)

            if batch is None:
                print("No pending Etsy payment backfill batches remain.")
                return

            print("")
            print(
                "Processing Etsy payment backfill batch: "
                f"{batch['batch_id']} "
                f"(sequence {batch['batch_sequence']}, "
                f"{batch['batch_receipt_count']} receipts)"
            )

            mark_batch_running(client, batch)

            return_code, output = run_payment_backfill_script(batch)

            if return_code == 0:
                counts = get_batch_counts(client, batch)
                mark_batch_complete(client, batch, counts)

                completed_batches += 1

                print(f"Marked Etsy payment batch COMPLETE: {batch['batch_id']}")
                print(f"Payment rows: {counts['payment_row_count']}")
                print(f"Skipped 404 receipts: {counts['skipped_404_count']}")
                print(
                    "Zero payment responses: "
                    f"{counts['zero_payment_response_count']}"
                )
                print(f"Completed batches this run: {completed_batches}")

                continue

            if is_rate_limit_error(return_code, output):
                mark_batch_rate_limited(
                    client=client,
                    batch=batch,
                    error_message=output[-6000:],
                )

                print(f"Marked Etsy payment batch RATE_LIMIT: {batch['batch_id']}")
                print(f"Completed batches before rate limit: {completed_batches}")

                return

            mark_batch_failed(
                client=client,
                batch=batch,
                error_message=output[-6000:],
            )

            raise RuntimeError(
                "Etsy payment backfill script failed for batch "
                f"{batch['batch_id']}."
            )

    process_batches_until_stopped()