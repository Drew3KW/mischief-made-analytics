from __future__ import annotations

import argparse
import os
import sys
from datetime import UTC, datetime
from typing import Any
import time

from google.cloud import bigquery

from etsy_orders_landing import (
    DEFAULT_DATASET,
    DEFAULT_PROJECT_ID,
    RateLimitError,
    append_rows,
    build_payment_row,
    etsy_get,
    load_local_env,
    now_timestamp,
    payment_schema,
    refresh_access_token,
    require_env,
)

STATE_TABLE = "etsy_historical_payment_backfill_batches"
RECEIPTS_TABLE = "etsy_receipts_api_latest"
LATEST_PAYMENTS_TABLE = "etsy_receipt_payments_api_latest"
PAYMENT_CANDIDATE_TABLE = "etsy_receipt_payments_api_payment_backfill_candidate"
SKIPPED_RECEIPTS_TABLE = "etsy_receipt_payments_api_payment_backfill_skipped_receipts"


def skipped_receipt_schema() -> list[bigquery.SchemaField]:
    return [
        bigquery.SchemaField("receipt_id", "INT64"),
        bigquery.SchemaField("batch_id", "STRING"),
        bigquery.SchemaField("skip_reason", "STRING"),
        bigquery.SchemaField("http_status", "INT64"),
        bigquery.SchemaField("error_message", "STRING"),
        bigquery.SchemaField("skipped_at", "TIMESTAMP"),
    ]


def state_table_id(project_id: str, dataset: str) -> str:
    return f"{project_id}.{dataset}.{STATE_TABLE}"


def receipt_table_id(project_id: str, dataset: str) -> str:
    return f"{project_id}.{dataset}.{RECEIPTS_TABLE}"


def latest_payment_table_id(project_id: str, dataset: str) -> str:
    return f"{project_id}.{dataset}.{LATEST_PAYMENTS_TABLE}"


def payment_candidate_table_id(project_id: str, dataset: str) -> str:
    return f"{project_id}.{dataset}.{PAYMENT_CANDIDATE_TABLE}"


def skipped_receipts_table_id(project_id: str, dataset: str) -> str:
    return f"{project_id}.{dataset}.{SKIPPED_RECEIPTS_TABLE}"


def run_query(
    client: bigquery.Client,
    query: str,
    query_parameters: list[bigquery.ScalarQueryParameter],
) -> list[bigquery.table.Row]:
    job_config = bigquery.QueryJobConfig(query_parameters=query_parameters)
    job = client.query(query, job_config=job_config)
    return list(job.result())


def get_batch_receipt_ids(
    client: bigquery.Client,
    project_id: str,
    dataset: str,
    batch_id: str,
    limit_receipts: int | None,
) -> list[int]:
    limit_clause = ""
    if limit_receipts is not None:
        limit_clause = "LIMIT @limit_receipts"

    query = f"""
    WITH selected_batch AS (
        SELECT
            batch_id,
            batch_start_position,
            batch_end_position
        FROM `{state_table_id(project_id, dataset)}`
        WHERE batch_id = @batch_id
    ),

    existing_latest_payment_receipts AS (
        SELECT DISTINCT
            receipt_id
        FROM `{latest_payment_table_id(project_id, dataset)}`
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
        FROM `{receipt_table_id(project_id, dataset)}` AS receipts
        LEFT JOIN existing_latest_payment_receipts AS latest_payments
            ON receipts.receipt_id = latest_payments.receipt_id
        WHERE receipts.receipt_id IS NOT NULL
          AND latest_payments.receipt_id IS NULL
          AND COALESCE(receipts.created_timestamp, receipts.create_timestamp) IS NOT NULL
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

    already_processed_receipts AS (
        SELECT DISTINCT
            receipt_id
        FROM `{payment_candidate_table_id(project_id, dataset)}`
        WHERE receipt_id IS NOT NULL

        UNION DISTINCT

        SELECT DISTINCT
            receipt_id
        FROM `{skipped_receipts_table_id(project_id, dataset)}`
        WHERE receipt_id IS NOT NULL
    )

    SELECT
        batch_receipts.receipt_id
    FROM batch_receipts
    LEFT JOIN already_processed_receipts
        ON batch_receipts.receipt_id = already_processed_receipts.receipt_id
    WHERE already_processed_receipts.receipt_id IS NULL
    ORDER BY batch_receipts.receipt_id
    {limit_clause}
    """

    parameters: list[bigquery.ScalarQueryParameter] = [
        bigquery.ScalarQueryParameter("batch_id", "STRING", batch_id),
    ]

    if limit_receipts is not None:
        parameters.append(
            bigquery.ScalarQueryParameter("limit_receipts", "INT64", limit_receipts)
        )

    rows = run_query(
        client=client,
        query=query,
        query_parameters=parameters,
    )

    return [int(row["receipt_id"]) for row in rows]


def build_skipped_receipt_row(
    receipt_id: int,
    batch_id: str,
    skip_reason: str,
    http_status: int | None,
    error_message: str,
    skipped_at: str,
) -> dict[str, Any]:
    return {
        "receipt_id": receipt_id,
        "batch_id": batch_id,
        "skip_reason": skip_reason,
        "http_status": http_status,
        "error_message": error_message,
        "skipped_at": skipped_at,
    }

def is_per_second_rate_limit_error(error: RateLimitError) -> bool:
    error_message = str(error).lower()

    return (
        "per second rate limit" in error_message
        or "exceeded per second" in error_message
        or "qps" in error_message
    )


def fetch_payment_payload_with_retry(
    access_token: str,
    shop_id: str,
    receipt_id: int,
    max_per_second_retries: int,
    per_second_retry_sleep_seconds: float,
) -> dict[str, Any]:
    attempt_count = 0

    while True:
        try:
            return etsy_get(
                f"/application/shops/{shop_id}/receipts/{receipt_id}/payments",
                access_token=access_token,
            )
        except RateLimitError as error:
            if not is_per_second_rate_limit_error(error):
                raise

            attempt_count += 1

            if attempt_count > max_per_second_retries:
                raise RuntimeError(
                    "Etsy per-second rate limit persisted after "
                    f"{max_per_second_retries} retries for receipt_id "
                    f"{receipt_id}."
                ) from error

            print(
                "Etsy per-second rate limit hit for receipt_id "
                f"{receipt_id}. Sleeping for "
                f"{per_second_retry_sleep_seconds} seconds before retry "
                f"{attempt_count} of {max_per_second_retries}."
            )

            time.sleep(per_second_retry_sleep_seconds)

def fetch_payment_rows_for_batch(
    access_token: str,
    shop_id: str,
    receipt_ids: list[int],
    batch_id: str,
    run_id: str,
    loaded_at: str,
    request_delay_seconds: float,
    max_per_second_retries: int,
    per_second_retry_sleep_seconds: float,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int, int]:
    payment_rows: list[dict[str, Any]] = []
    skipped_rows: list[dict[str, Any]] = []
    skipped_404_count = 0
    zero_payment_response_count = 0

    for receipt_id in receipt_ids:
        try:
            payload = fetch_payment_payload_with_retry(
                access_token=access_token,
                shop_id=shop_id,
                receipt_id=receipt_id,
                max_per_second_retries=max_per_second_retries,
                per_second_retry_sleep_seconds=per_second_retry_sleep_seconds,
            )
        except RateLimitError:
            raise
        except RuntimeError as error:
            error_message = str(error)

            if (
                "HTTP 404" in error_message
                and "Could not find a Shop Receipt" in error_message
            ):
                skipped_404_count += 1
                skipped_rows.append(
                    build_skipped_receipt_row(
                        receipt_id=receipt_id,
                        batch_id=batch_id,
                        skip_reason="HTTP_404",
                        http_status=404,
                        error_message=error_message,
                        skipped_at=loaded_at,
                    )
                )
                print(
                    "Skipping payment fetch for receipt_id "
                    f"{receipt_id}: Etsy payment endpoint returned 404."
                )
                continue

            raise

        results = payload.get("results", [])

        if not results:
            zero_payment_response_count += 1
            skipped_rows.append(
                build_skipped_receipt_row(
                    receipt_id=receipt_id,
                    batch_id=batch_id,
                    skip_reason="EMPTY_PAYMENT_RESPONSE",
                    http_status=None,
                    error_message="Etsy payment endpoint returned no payment rows.",
                    skipped_at=loaded_at,
                )
            )
            print(
                "Skipping payment fetch for receipt_id "
                f"{receipt_id}: Etsy payment endpoint returned no rows."
            )
            continue

        for payment in results:
            payment_rows.append(
                build_payment_row(
                    payment=payment,
                    run_id=run_id,
                    loaded_at=loaded_at,
                )
            )

        if request_delay_seconds > 0:
            time.sleep(request_delay_seconds)

    return payment_rows, skipped_rows, skipped_404_count, zero_payment_response_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Etsy receipt payments for one historical payment backfill batch."
    )

    parser.add_argument(
        "--batch-id",
        required=True,
        help="Batch ID from raw_load.etsy_historical_payment_backfill_batches.",
    )

    parser.add_argument(
        "--project-id",
        default=(
            os.environ.get("BIGQUERY_PROJECT_ID")
            or os.environ.get("GOOGLE_CLOUD_PROJECT")
            or DEFAULT_PROJECT_ID
        ),
        help="BigQuery project ID.",
    )

    parser.add_argument(
        "--dataset",
        default=DEFAULT_DATASET,
        help="BigQuery dataset for Etsy raw_load tables.",
    )

    parser.add_argument(
        "--limit-receipts",
        type=int,
        help="Optional test limit for receipt IDs processed from this batch.",
    )

    parser.add_argument(
        "--request-delay-seconds",
        type=float,
        default=0.35,
        help="Delay between Etsy payment requests.",
    )

    parser.add_argument(
        "--max-per-second-retries",
        type=int,
        default=6,
        help="Retry count for Etsy per-second rate limits.",
    )

    parser.add_argument(
        "--per-second-retry-sleep-seconds",
        type=float,
        default=10.0,
        help="Sleep duration before retrying after a per-second rate limit.",
    )    

    return parser.parse_args()


def main() -> None:
    load_local_env()
    args = parse_args()

    shop_id = require_env("ETSY_SHOP_ID")

    print("Starting Etsy payment backfill batch")
    print(f"Project: {args.project_id}")
    print(f"Dataset: {args.dataset}")
    print(f"Batch ID: {args.batch_id}")

    if args.limit_receipts is not None:
        print(f"Receipt test limit: {args.limit_receipts}")

    client = bigquery.Client(project=args.project_id)

    receipt_ids = get_batch_receipt_ids(
        client=client,
        project_id=args.project_id,
        dataset=args.dataset,
        batch_id=args.batch_id,
        limit_receipts=args.limit_receipts,
    )

    print(f"Receipt IDs remaining in batch: {len(receipt_ids)}")

    if not receipt_ids:
        print("No unprocessed receipt IDs remain for this batch.")
        return

    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    loaded_at = now_timestamp()
    access_token = refresh_access_token()

    try:
        (
            payment_rows,
            skipped_rows,
            skipped_404_count,
            zero_payment_response_count,
        ) = fetch_payment_rows_for_batch(
            access_token=access_token,
            shop_id=shop_id,
            receipt_ids=receipt_ids,
            batch_id=args.batch_id,
            run_id=run_id,
            loaded_at=loaded_at,
            request_delay_seconds=args.request_delay_seconds,
            max_per_second_retries=args.max_per_second_retries,
            per_second_retry_sleep_seconds=args.per_second_retry_sleep_seconds,
        )
    except RateLimitError as error:
        print("")
        print("Rate limit reached. The current payment batch stopped early.")
        print(str(error))
        sys.exit(2)

    append_rows(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
        table_name_value=PAYMENT_CANDIDATE_TABLE,
        rows=payment_rows,
        schema=payment_schema(),
    )

    append_rows(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
        table_name_value=SKIPPED_RECEIPTS_TABLE,
        rows=skipped_rows,
        schema=skipped_receipt_schema(),
    )

    print("")
    print("Etsy payment backfill batch completed successfully.")
    print(f"Receipt IDs processed: {len(receipt_ids)}")
    print(f"Payment rows appended: {len(payment_rows)}")
    print(f"Skipped 404 receipts: {skipped_404_count}")
    print(f"Zero payment responses: {zero_payment_response_count}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)