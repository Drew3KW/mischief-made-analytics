from __future__ import annotations

import os
import subprocess
from datetime import UTC, datetime

from airflow import DAG
from airflow.decorators import task
from google.cloud import bigquery


DAG_ID = "mm_etsy_historical_backfill_mvp"

PROJECT_ID = "mischief-made-analytics"
DATASET = "raw_load"
STATE_TABLE = "etsy_historical_backfill_chunks"

SCRIPT_PATH = "/opt/airflow/scripts/etsy_orders_landing.py"

DEFAULT_ARGS = {
    "owner": "airflow",
    "retries": 0,
}


def state_table_id() -> str:
    return f"{PROJECT_ID}.{DATASET}.{STATE_TABLE}"


def run_query(client: bigquery.Client, query: str) -> list[bigquery.table.Row]:
    job = client.query(query)
    return list(job.result())


def get_next_pending_chunk(client: bigquery.Client) -> dict[str, str] | None:
    query = f"""
    SELECT
        chunk_id,
        chunk_start_date,
        chunk_end_date
    FROM `{state_table_id()}`
    WHERE chunk_status = 'PENDING'
    ORDER BY chunk_start_date
    LIMIT 1
    """

    rows = run_query(client, query)

    if not rows:
        return None

    row = rows[0]

    return {
        "chunk_id": row["chunk_id"],
        "chunk_start_date": row["chunk_start_date"].isoformat(),
        "chunk_end_date": row["chunk_end_date"].isoformat(),
    }


def reset_old_rate_limits(client: bigquery.Client) -> None:
    query = f"""
    UPDATE `{state_table_id()}`
    SET
        chunk_status = 'PENDING',
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP()
    WHERE chunk_status = 'RATE_LIMIT'
      AND DATE(updated_at, 'America/Los_Angeles')
          < CURRENT_DATE('America/Los_Angeles')
    """

    client.query(query).result()


def today_rate_limit_exists(client: bigquery.Client) -> bool:
    query = f"""
    SELECT
        COUNT(*) AS todays_rate_limit_count
    FROM `{state_table_id()}`
    WHERE chunk_status = 'RATE_LIMIT'
      AND DATE(updated_at, 'America/Los_Angeles')
          = CURRENT_DATE('America/Los_Angeles')
    """

    rows = run_query(client, query)

    return rows[0]["todays_rate_limit_count"] > 0


def mark_chunk_running(client: bigquery.Client, chunk: dict[str, str]) -> None:
    query = f"""
    UPDATE `{state_table_id()}`
    SET
        chunk_status = 'RUNNING',
        started_at = CURRENT_TIMESTAMP(),
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP()
    WHERE chunk_id = @chunk_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("chunk_id", "STRING", chunk["chunk_id"]),
        ]
    )

    client.query(query, job_config=job_config).result()


def mark_chunk_rate_limited(
    client: bigquery.Client,
    chunk: dict[str, str],
    error_message: str,
) -> None:
    query = f"""
    UPDATE `{state_table_id()}`
    SET
        chunk_status = 'RATE_LIMIT',
        error_message = @error_message,
        updated_at = CURRENT_TIMESTAMP()
    WHERE chunk_id = @chunk_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("chunk_id", "STRING", chunk["chunk_id"]),
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
        ]
    )

    client.query(query, job_config=job_config).result()


def mark_chunk_failed(
    client: bigquery.Client,
    chunk: dict[str, str],
    error_message: str,
) -> None:
    query = f"""
    UPDATE `{state_table_id()}`
    SET
        chunk_status = 'FAILED',
        error_message = @error_message,
        updated_at = CURRENT_TIMESTAMP()
    WHERE chunk_id = @chunk_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("chunk_id", "STRING", chunk["chunk_id"]),
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message),
        ]
    )

    client.query(query, job_config=job_config).result()


def get_chunk_counts(
    client: bigquery.Client,
    chunk: dict[str, str],
) -> dict[str, int]:
    count_query = f"""
    WITH receipt_counts AS (
        SELECT
            COUNT(*) AS receipt_row_count
        FROM `{PROJECT_ID}.{DATASET}.etsy_receipts_api_backfill_candidate`
        WHERE DATE(TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp)))
            BETWEEN @chunk_start_date AND @chunk_end_date
    ),

    transaction_counts AS (
        SELECT
            COUNT(*) AS transaction_row_count
        FROM `{PROJECT_ID}.{DATASET}.etsy_receipt_transactions_api_backfill_candidate`
        WHERE DATE(TIMESTAMP_SECONDS(COALESCE(created_timestamp, create_timestamp)))
            BETWEEN @chunk_start_date AND @chunk_end_date
    ),

    payment_counts AS (
        SELECT
            COUNT(*) AS payment_row_count
        FROM `{PROJECT_ID}.{DATASET}.etsy_receipt_payments_api_backfill_candidate` AS payments
        INNER JOIN `{PROJECT_ID}.{DATASET}.etsy_receipts_api_backfill_candidate` AS receipts
            ON payments.receipt_id = receipts.receipt_id
        WHERE DATE(TIMESTAMP_SECONDS(COALESCE(receipts.created_timestamp, receipts.create_timestamp)))
            BETWEEN @chunk_start_date AND @chunk_end_date
    )

    SELECT
        receipt_row_count,
        transaction_row_count,
        payment_row_count
    FROM receipt_counts
    CROSS JOIN transaction_counts
    CROSS JOIN payment_counts
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter(
                "chunk_start_date",
                "DATE",
                chunk["chunk_start_date"],
            ),
            bigquery.ScalarQueryParameter(
                "chunk_end_date",
                "DATE",
                chunk["chunk_end_date"],
            ),
        ]
    )

    rows = list(client.query(count_query, job_config=job_config).result())
    counts = rows[0]

    return {
        "receipt_row_count": counts["receipt_row_count"],
        "transaction_row_count": counts["transaction_row_count"],
        "payment_row_count": counts["payment_row_count"],
    }


def mark_chunk_complete(
    client: bigquery.Client,
    chunk: dict[str, str],
    counts: dict[str, int],
) -> None:
    query = f"""
    UPDATE `{state_table_id()}`
    SET
        chunk_status = 'COMPLETE',
        completed_at = CURRENT_TIMESTAMP(),
        receipt_row_count = @receipt_row_count,
        transaction_row_count = @transaction_row_count,
        payment_row_count = @payment_row_count,
        skipped_payment_count = 0,
        error_message = NULL,
        updated_at = CURRENT_TIMESTAMP()
    WHERE chunk_id = @chunk_id
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("chunk_id", "STRING", chunk["chunk_id"]),
            bigquery.ScalarQueryParameter(
                "receipt_row_count",
                "INT64",
                counts["receipt_row_count"],
            ),
            bigquery.ScalarQueryParameter(
                "transaction_row_count",
                "INT64",
                counts["transaction_row_count"],
            ),
            bigquery.ScalarQueryParameter(
                "payment_row_count",
                "INT64",
                counts["payment_row_count"],
            ),
        ]
    )

    client.query(query, job_config=job_config).result()


def run_landing_script(chunk: dict[str, str]) -> tuple[int, str]:
    command = [
        "python",
        SCRIPT_PATH,
        "--start-date",
        chunk["chunk_start_date"],
        "--end-date",
        chunk["chunk_end_date"],
        "--chunk-days",
        "30",
        "--table-suffix",
        "backfill_candidate",
        "--write-mode",
        "append",
        "--limit",
        "100",
        "--max-pages",
        "20",
        "--skip-payments",
    ]

    print("Running Etsy backfill command:")
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
    description="Process Etsy historical receipts/transactions backfill chunks until rate limit or completion.",
    start_date=datetime(2026, 5, 20, 0, 0, tzinfo=UTC),
    schedule="30 20 * * *",
    catchup=False,
    tags=["mischief-made", "etsy", "backfill", "mvp"],
) as dag:

    @task
    def process_chunks_until_stopped() -> None:
        client = bigquery.Client(project=PROJECT_ID)

        reset_old_rate_limits(client)

        if today_rate_limit_exists(client):
            print(
                "An Etsy backfill chunk already hit the rate limit today. "
                "No additional chunks will be processed until a future scheduled run."
            )
            return

        completed_chunks = 0

        while True:
            chunk = get_next_pending_chunk(client)

            if chunk is None:
                print("No pending Etsy backfill chunks remain.")
                return

            print("")
            print(
                "Processing Etsy backfill chunk: "
                f"{chunk['chunk_start_date']} to {chunk['chunk_end_date']}"
            )

            mark_chunk_running(client, chunk)

            return_code, output = run_landing_script(chunk)

            if return_code == 0:
                counts = get_chunk_counts(client, chunk)
                mark_chunk_complete(client, chunk, counts)

                completed_chunks += 1

                print(
                    "Marked Etsy backfill chunk COMPLETE: "
                    f"{chunk['chunk_start_date']} to {chunk['chunk_end_date']}"
                )
                print(f"Receipt rows: {counts['receipt_row_count']}")
                print(f"Transaction rows: {counts['transaction_row_count']}")
                print(f"Payment rows: {counts['payment_row_count']}")
                print(f"Completed chunks this run: {completed_chunks}")

                continue

            if is_rate_limit_error(return_code, output):
                mark_chunk_rate_limited(
                    client=client,
                    chunk=chunk,
                    error_message=output[-6000:],
                )

                print(
                    "Marked Etsy backfill chunk RATE_LIMIT: "
                    f"{chunk['chunk_start_date']} to {chunk['chunk_end_date']}"
                )
                print(f"Completed chunks before rate limit: {completed_chunks}")
                return

            mark_chunk_failed(
                client=client,
                chunk=chunk,
                error_message=output[-6000:],
            )

            raise RuntimeError(
                "Etsy backfill script failed for chunk "
                f"{chunk['chunk_start_date']} to {chunk['chunk_end_date']}."
            )


    process_chunks_until_stopped()