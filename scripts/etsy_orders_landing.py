from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

from google.cloud import bigquery


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = PROJECT_ROOT / ".env"
TOKEN_PATH = PROJECT_ROOT / "local_data" / "etsy_api_spike" / "oauth_token.json"

BASE_URL = "https://api.etsy.com/v3"
OAUTH_TOKEN_URL = "https://api.etsy.com/v3/public/oauth/token"

DEFAULT_PROJECT_ID = "mischief-made-analytics"
DEFAULT_DATASET = "raw_load"

RECEIPTS_TABLE = "etsy_receipts_api_latest"
TRANSACTIONS_TABLE = "etsy_receipt_transactions_api_latest"
PAYMENTS_TABLE = "etsy_receipt_payments_api_latest"


def load_local_env() -> None:
    # This reads the local .env file without requiring python-dotenv.
    if not ENV_PATH.exists():
        return

    for raw_line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        if key and key not in os.environ:
            os.environ[key] = value


def require_env(name: str) -> str:
    value = os.environ.get(name)

    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")

    return value


def json_text(value: Any) -> str | None:
    # BigQuery can store raw nested data safely as a JSON string.
    if value is None:
        return None

    return json.dumps(value, sort_keys=True)


def money_amount(value: dict[str, Any] | None) -> str | None:
    # Etsy money values usually have amount, divisor, and currency_code.
    # Example: amount 1234 and divisor 100 means 12.34.
    if not isinstance(value, dict):
        return None

    amount = value.get("amount")
    divisor = value.get("divisor")

    if amount is None or divisor in (None, 0):
        return None

    return str(Decimal(str(amount)) / Decimal(str(divisor)))


def money_currency(value: dict[str, Any] | None) -> str | None:
    if not isinstance(value, dict):
        return None

    return value.get("currency_code")


def now_timestamp() -> str:
    return datetime.now(UTC).isoformat()


def read_saved_token() -> dict[str, Any]:
    if not TOKEN_PATH.exists():
        return {}

    return json.loads(TOKEN_PATH.read_text(encoding="utf-8"))


def write_saved_token(payload: dict[str, Any]) -> None:
    TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def request_json(
    method: str,
    url: str,
    headers: dict[str, str] | None = None,
    form_data: dict[str, str] | None = None,
) -> tuple[Any, dict[str, str]]:
    body = None

    if form_data is not None:
        body = urllib.parse.urlencode(form_data).encode("utf-8")

    request = urllib.request.Request(
        url=url,
        data=body,
        headers=headers or {},
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            response_body = response.read().decode("utf-8")
            payload = json.loads(response_body) if response_body else {}
            return payload, dict(response.headers)

    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8")
        raise RuntimeError(f"HTTP {error.code} {error.reason}: {error_body}") from error


def get_refresh_token() -> str:
    env_token = os.environ.get("ETSY_REFRESH_TOKEN")

    if env_token:
        return env_token

    saved_token = read_saved_token()
    refresh_token = saved_token.get("refresh_token")

    if refresh_token:
        return refresh_token

    raise RuntimeError(
        "Missing Etsy refresh token. Run scripts/etsy_api_probe.py exchange-code first, "
        "or set ETSY_REFRESH_TOKEN in local .env."
    )


def refresh_access_token() -> str:
    form_data = {
        "grant_type": "refresh_token",
        "client_id": require_env("ETSY_API_KEYSTRING"),
        "refresh_token": get_refresh_token(),
    }

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    }

    payload, _ = request_json(
        "POST",
        OAUTH_TOKEN_URL,
        headers=headers,
        form_data=form_data,
    )

    write_saved_token(payload)

    access_token = payload.get("access_token")

    if not access_token:
        raise RuntimeError("Etsy token refresh did not return an access_token.")

    return access_token


def etsy_headers(access_token: str) -> dict[str, str]:
    keystring = require_env("ETSY_API_KEYSTRING")
    shared_secret = os.environ.get("ETSY_SHARED_SECRET", "")

    api_key_header = f"{keystring}:{shared_secret}" if shared_secret else keystring

    return {
        "Accept": "application/json",
        "Authorization": f"Bearer {access_token}",
        "x-api-key": api_key_header,
    }


def etsy_get(
    path: str,
    access_token: str,
    params: dict[str, Any] | None = None,
) -> Any:
    clean_params = {}

    for key, value in (params or {}).items():
        if value is not None:
            clean_params[key] = value

    query_string = urllib.parse.urlencode(clean_params, doseq=True)
    url = f"{BASE_URL}{path}"

    if query_string:
        url = f"{url}?{query_string}"

    payload, _ = request_json(
        "GET",
        url,
        headers=etsy_headers(access_token),
    )

    return payload


def unix_range_for_days(days: int) -> tuple[int, int]:
    max_created = int(time.time())
    min_created = max_created - (days * 24 * 60 * 60)
    return min_created, max_created


def fetch_receipts(
    access_token: str,
    shop_id: str,
    days: int,
    limit: int,
    max_pages: int,
) -> list[dict[str, Any]]:
    min_created, max_created = unix_range_for_days(days)
    receipts: list[dict[str, Any]] = []

    for page_number in range(max_pages):
        offset = page_number * limit

        params = {
            "min_created": min_created,
            "max_created": max_created,
            "limit": limit,
            "offset": offset,
            "sort_on": "created",
            "sort_order": "desc",
        }

        payload = etsy_get(
            f"/application/shops/{shop_id}/receipts",
            access_token=access_token,
            params=params,
        )

        results = payload.get("results", [])

        if not results:
            break

        receipts.extend(results)

        api_count = payload.get("count")

        if api_count is not None and len(receipts) >= int(api_count):
            break

        if len(results) < limit:
            break

    return receipts


def fetch_payment_rows(
    access_token: str,
    shop_id: str,
    receipt_ids: list[int],
    run_id: str,
    loaded_at: str,
) -> list[dict[str, Any]]:
    payment_rows: list[dict[str, Any]] = []
    skipped_receipt_ids: list[int] = []

    for receipt_id in receipt_ids:
        try:
            payload = etsy_get(
                f"/application/shops/{shop_id}/receipts/{receipt_id}/payments",
                access_token=access_token,
            )

        except RuntimeError as error:
            error_message = str(error)

            if "HTTP 404" in error_message and "Could not find a Shop Receipt" in error_message:
                skipped_receipt_ids.append(receipt_id)
                print(
                    "Skipping payment fetch for receipt_id "
                    f"{receipt_id}: Etsy payment endpoint returned 404."
                )
                continue

            raise

        for payment in payload.get("results", []):
            payment_rows.append(build_payment_row(payment, run_id, loaded_at))

    if skipped_receipt_ids:
        print(
            "Skipped payment fetches for "
            f"{len(skipped_receipt_ids)} receipt_id values."
        )

    return payment_rows


def build_receipt_row(
    receipt: dict[str, Any],
    run_id: str,
    loaded_at: str,
) -> dict[str, Any]:
    return {
        "landing_run_id": run_id,
        "landing_loaded_at": loaded_at,
        "receipt_id": receipt.get("receipt_id"),
        "receipt_type": receipt.get("receipt_type"),
        "status": receipt.get("status"),
        "is_paid": receipt.get("is_paid"),
        "is_shipped": receipt.get("is_shipped"),
        "buyer_user_id": receipt.get("buyer_user_id"),
        "buyer_email": receipt.get("buyer_email"),
        "seller_user_id": receipt.get("seller_user_id"),
        "seller_email": receipt.get("seller_email"),
        "payment_email": receipt.get("payment_email"),
        "payment_method": receipt.get("payment_method"),
        "create_timestamp": receipt.get("create_timestamp"),
        "created_timestamp": receipt.get("created_timestamp"),
        "update_timestamp": receipt.get("update_timestamp"),
        "updated_timestamp": receipt.get("updated_timestamp"),
        "name": receipt.get("name"),
        "first_line": receipt.get("first_line"),
        "second_line": receipt.get("second_line"),
        "city": receipt.get("city"),
        "state": receipt.get("state"),
        "zip": receipt.get("zip"),
        "country_iso": receipt.get("country_iso"),
        "formatted_address": receipt.get("formatted_address"),
        "is_gift": receipt.get("is_gift"),
        "gift_message": receipt.get("gift_message"),
        "gift_sender": receipt.get("gift_sender"),
        "message_from_buyer": receipt.get("message_from_buyer"),
        "message_from_payment": receipt.get("message_from_payment"),
        "message_from_seller": receipt.get("message_from_seller"),
        "discount_amt": money_amount(receipt.get("discount_amt")),
        "discount_amt_currency": money_currency(receipt.get("discount_amt")),
        "subtotal": money_amount(receipt.get("subtotal")),
        "subtotal_currency": money_currency(receipt.get("subtotal")),
        "grandtotal": money_amount(receipt.get("grandtotal")),
        "grandtotal_currency": money_currency(receipt.get("grandtotal")),
        "total_price": money_amount(receipt.get("total_price")),
        "total_price_currency": money_currency(receipt.get("total_price")),
        "total_shipping_cost": money_amount(receipt.get("total_shipping_cost")),
        "total_shipping_cost_currency": money_currency(receipt.get("total_shipping_cost")),
        "total_tax_cost": money_amount(receipt.get("total_tax_cost")),
        "total_tax_cost_currency": money_currency(receipt.get("total_tax_cost")),
        "total_vat_cost": money_amount(receipt.get("total_vat_cost")),
        "total_vat_cost_currency": money_currency(receipt.get("total_vat_cost")),
        "gift_wrap_price": money_amount(receipt.get("gift_wrap_price")),
        "gift_wrap_price_currency": money_currency(receipt.get("gift_wrap_price")),
        "refunds_json": json_text(receipt.get("refunds")),
        "shipments_json": json_text(receipt.get("shipments")),
        "transactions_json": json_text(receipt.get("transactions")),
        "raw_json": json_text(receipt),
    }


def build_transaction_row(
    transaction: dict[str, Any],
    parent_receipt_id: int | None,
    run_id: str,
    loaded_at: str,
) -> dict[str, Any]:
    return {
        "landing_run_id": run_id,
        "landing_loaded_at": loaded_at,
        "transaction_id": transaction.get("transaction_id"),
        "receipt_id": transaction.get("receipt_id") or parent_receipt_id,
        "transaction_type": transaction.get("transaction_type"),
        "buyer_user_id": transaction.get("buyer_user_id"),
        "seller_user_id": transaction.get("seller_user_id"),
        "listing_id": transaction.get("listing_id"),
        "listing_image_id": transaction.get("listing_image_id"),
        "product_id": transaction.get("product_id"),
        "sku": transaction.get("sku"),
        "title": transaction.get("title"),
        "description": transaction.get("description"),
        "quantity": transaction.get("quantity"),
        "is_digital": transaction.get("is_digital"),
        "create_timestamp": transaction.get("create_timestamp"),
        "created_timestamp": transaction.get("created_timestamp"),
        "paid_timestamp": transaction.get("paid_timestamp"),
        "shipped_timestamp": transaction.get("shipped_timestamp"),
        "expected_ship_date": transaction.get("expected_ship_date"),
        "min_processing_days": transaction.get("min_processing_days"),
        "max_processing_days": transaction.get("max_processing_days"),
        "shipping_method": transaction.get("shipping_method"),
        "shipping_profile_id": transaction.get("shipping_profile_id"),
        "shipping_upgrade": transaction.get("shipping_upgrade"),
        "price": money_amount(transaction.get("price")),
        "price_currency": money_currency(transaction.get("price")),
        "shipping_cost": money_amount(transaction.get("shipping_cost")),
        "shipping_cost_currency": money_currency(transaction.get("shipping_cost")),
        "buyer_coupon": transaction.get("buyer_coupon"),
        "shop_coupon": transaction.get("shop_coupon"),
        "file_data_json": json_text(transaction.get("file_data")),
        "product_data_json": json_text(transaction.get("product_data")),
        "variations_json": json_text(transaction.get("variations")),
        "raw_json": json_text(transaction),
    }


def build_payment_row(
    payment: dict[str, Any],
    run_id: str,
    loaded_at: str,
) -> dict[str, Any]:
    return {
        "landing_run_id": run_id,
        "landing_loaded_at": loaded_at,
        "payment_id": payment.get("payment_id"),
        "receipt_id": payment.get("receipt_id"),
        "shop_id": payment.get("shop_id"),
        "buyer_user_id": payment.get("buyer_user_id"),
        "status": payment.get("status"),
        "currency": payment.get("currency"),
        "buyer_currency": payment.get("buyer_currency"),
        "shop_currency": payment.get("shop_currency"),
        "billing_address_id": payment.get("billing_address_id"),
        "shipping_address_id": payment.get("shipping_address_id"),
        "shipping_user_id": payment.get("shipping_user_id"),
        "create_timestamp": payment.get("create_timestamp"),
        "created_timestamp": payment.get("created_timestamp"),
        "update_timestamp": payment.get("update_timestamp"),
        "updated_timestamp": payment.get("updated_timestamp"),
        "shipped_timestamp": payment.get("shipped_timestamp"),
        "amount_gross": money_amount(payment.get("amount_gross")),
        "amount_gross_currency": money_currency(payment.get("amount_gross")),
        "amount_fees": money_amount(payment.get("amount_fees")),
        "amount_fees_currency": money_currency(payment.get("amount_fees")),
        "amount_net": money_amount(payment.get("amount_net")),
        "amount_net_currency": money_currency(payment.get("amount_net")),
        "adjusted_gross": money_amount(payment.get("adjusted_gross")),
        "adjusted_gross_currency": money_currency(payment.get("adjusted_gross")),
        "adjusted_fees": money_amount(payment.get("adjusted_fees")),
        "adjusted_fees_currency": money_currency(payment.get("adjusted_fees")),
        "adjusted_net": money_amount(payment.get("adjusted_net")),
        "adjusted_net_currency": money_currency(payment.get("adjusted_net")),
        "posted_gross": money_amount(payment.get("posted_gross")),
        "posted_gross_currency": money_currency(payment.get("posted_gross")),
        "posted_fees": money_amount(payment.get("posted_fees")),
        "posted_fees_currency": money_currency(payment.get("posted_fees")),
        "posted_net": money_amount(payment.get("posted_net")),
        "posted_net_currency": money_currency(payment.get("posted_net")),
        "payment_adjustments_json": json_text(payment.get("payment_adjustments")),
        "raw_json": json_text(payment),
    }


def receipt_schema() -> list[bigquery.SchemaField]:
    return [
        bigquery.SchemaField("landing_run_id", "STRING"),
        bigquery.SchemaField("landing_loaded_at", "TIMESTAMP"),
        bigquery.SchemaField("receipt_id", "INT64"),
        bigquery.SchemaField("receipt_type", "INT64"),
        bigquery.SchemaField("status", "STRING"),
        bigquery.SchemaField("is_paid", "BOOL"),
        bigquery.SchemaField("is_shipped", "BOOL"),
        bigquery.SchemaField("buyer_user_id", "INT64"),
        bigquery.SchemaField("buyer_email", "STRING"),
        bigquery.SchemaField("seller_user_id", "INT64"),
        bigquery.SchemaField("seller_email", "STRING"),
        bigquery.SchemaField("payment_email", "STRING"),
        bigquery.SchemaField("payment_method", "STRING"),
        bigquery.SchemaField("create_timestamp", "INT64"),
        bigquery.SchemaField("created_timestamp", "INT64"),
        bigquery.SchemaField("update_timestamp", "INT64"),
        bigquery.SchemaField("updated_timestamp", "INT64"),
        bigquery.SchemaField("name", "STRING"),
        bigquery.SchemaField("first_line", "STRING"),
        bigquery.SchemaField("second_line", "STRING"),
        bigquery.SchemaField("city", "STRING"),
        bigquery.SchemaField("state", "STRING"),
        bigquery.SchemaField("zip", "STRING"),
        bigquery.SchemaField("country_iso", "STRING"),
        bigquery.SchemaField("formatted_address", "STRING"),
        bigquery.SchemaField("is_gift", "BOOL"),
        bigquery.SchemaField("gift_message", "STRING"),
        bigquery.SchemaField("gift_sender", "STRING"),
        bigquery.SchemaField("message_from_buyer", "STRING"),
        bigquery.SchemaField("message_from_payment", "STRING"),
        bigquery.SchemaField("message_from_seller", "STRING"),
        bigquery.SchemaField("discount_amt", "NUMERIC"),
        bigquery.SchemaField("discount_amt_currency", "STRING"),
        bigquery.SchemaField("subtotal", "NUMERIC"),
        bigquery.SchemaField("subtotal_currency", "STRING"),
        bigquery.SchemaField("grandtotal", "NUMERIC"),
        bigquery.SchemaField("grandtotal_currency", "STRING"),
        bigquery.SchemaField("total_price", "NUMERIC"),
        bigquery.SchemaField("total_price_currency", "STRING"),
        bigquery.SchemaField("total_shipping_cost", "NUMERIC"),
        bigquery.SchemaField("total_shipping_cost_currency", "STRING"),
        bigquery.SchemaField("total_tax_cost", "NUMERIC"),
        bigquery.SchemaField("total_tax_cost_currency", "STRING"),
        bigquery.SchemaField("total_vat_cost", "NUMERIC"),
        bigquery.SchemaField("total_vat_cost_currency", "STRING"),
        bigquery.SchemaField("gift_wrap_price", "NUMERIC"),
        bigquery.SchemaField("gift_wrap_price_currency", "STRING"),
        bigquery.SchemaField("refunds_json", "STRING"),
        bigquery.SchemaField("shipments_json", "STRING"),
        bigquery.SchemaField("transactions_json", "STRING"),
        bigquery.SchemaField("raw_json", "STRING"),
    ]


def transaction_schema() -> list[bigquery.SchemaField]:
    return [
        bigquery.SchemaField("landing_run_id", "STRING"),
        bigquery.SchemaField("landing_loaded_at", "TIMESTAMP"),
        bigquery.SchemaField("transaction_id", "INT64"),
        bigquery.SchemaField("receipt_id", "INT64"),
        bigquery.SchemaField("transaction_type", "STRING"),
        bigquery.SchemaField("buyer_user_id", "INT64"),
        bigquery.SchemaField("seller_user_id", "INT64"),
        bigquery.SchemaField("listing_id", "INT64"),
        bigquery.SchemaField("listing_image_id", "INT64"),
        bigquery.SchemaField("product_id", "INT64"),
        bigquery.SchemaField("sku", "STRING"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("description", "STRING"),
        bigquery.SchemaField("quantity", "INT64"),
        bigquery.SchemaField("is_digital", "BOOL"),
        bigquery.SchemaField("create_timestamp", "INT64"),
        bigquery.SchemaField("created_timestamp", "INT64"),
        bigquery.SchemaField("paid_timestamp", "INT64"),
        bigquery.SchemaField("shipped_timestamp", "INT64"),
        bigquery.SchemaField("expected_ship_date", "INT64"),
        bigquery.SchemaField("min_processing_days", "INT64"),
        bigquery.SchemaField("max_processing_days", "INT64"),
        bigquery.SchemaField("shipping_method", "STRING"),
        bigquery.SchemaField("shipping_profile_id", "INT64"),
        bigquery.SchemaField("shipping_upgrade", "STRING"),
        bigquery.SchemaField("price", "NUMERIC"),
        bigquery.SchemaField("price_currency", "STRING"),
        bigquery.SchemaField("shipping_cost", "NUMERIC"),
        bigquery.SchemaField("shipping_cost_currency", "STRING"),
        bigquery.SchemaField("buyer_coupon", "NUMERIC"),
        bigquery.SchemaField("shop_coupon", "NUMERIC"),
        bigquery.SchemaField("file_data_json", "STRING"),
        bigquery.SchemaField("product_data_json", "STRING"),
        bigquery.SchemaField("variations_json", "STRING"),
        bigquery.SchemaField("raw_json", "STRING"),
    ]


def payment_schema() -> list[bigquery.SchemaField]:
    return [
        bigquery.SchemaField("landing_run_id", "STRING"),
        bigquery.SchemaField("landing_loaded_at", "TIMESTAMP"),
        bigquery.SchemaField("payment_id", "INT64"),
        bigquery.SchemaField("receipt_id", "INT64"),
        bigquery.SchemaField("shop_id", "INT64"),
        bigquery.SchemaField("buyer_user_id", "INT64"),
        bigquery.SchemaField("status", "STRING"),
        bigquery.SchemaField("currency", "STRING"),
        bigquery.SchemaField("buyer_currency", "STRING"),
        bigquery.SchemaField("shop_currency", "STRING"),
        bigquery.SchemaField("billing_address_id", "INT64"),
        bigquery.SchemaField("shipping_address_id", "INT64"),
        bigquery.SchemaField("shipping_user_id", "INT64"),
        bigquery.SchemaField("create_timestamp", "INT64"),
        bigquery.SchemaField("created_timestamp", "INT64"),
        bigquery.SchemaField("update_timestamp", "INT64"),
        bigquery.SchemaField("updated_timestamp", "INT64"),
        bigquery.SchemaField("shipped_timestamp", "INT64"),
        bigquery.SchemaField("amount_gross", "NUMERIC"),
        bigquery.SchemaField("amount_gross_currency", "STRING"),
        bigquery.SchemaField("amount_fees", "NUMERIC"),
        bigquery.SchemaField("amount_fees_currency", "STRING"),
        bigquery.SchemaField("amount_net", "NUMERIC"),
        bigquery.SchemaField("amount_net_currency", "STRING"),
        bigquery.SchemaField("adjusted_gross", "NUMERIC"),
        bigquery.SchemaField("adjusted_gross_currency", "STRING"),
        bigquery.SchemaField("adjusted_fees", "NUMERIC"),
        bigquery.SchemaField("adjusted_fees_currency", "STRING"),
        bigquery.SchemaField("adjusted_net", "NUMERIC"),
        bigquery.SchemaField("adjusted_net_currency", "STRING"),
        bigquery.SchemaField("posted_gross", "NUMERIC"),
        bigquery.SchemaField("posted_gross_currency", "STRING"),
        bigquery.SchemaField("posted_fees", "NUMERIC"),
        bigquery.SchemaField("posted_fees_currency", "STRING"),
        bigquery.SchemaField("posted_net", "NUMERIC"),
        bigquery.SchemaField("posted_net_currency", "STRING"),
        bigquery.SchemaField("payment_adjustments_json", "STRING"),
        bigquery.SchemaField("raw_json", "STRING"),
    ]


def ensure_dataset(client: bigquery.Client, project_id: str, dataset_name: str) -> None:
    dataset_id = f"{project_id}.{dataset_name}"
    dataset = bigquery.Dataset(dataset_id)
    dataset.location = "US"

    client.create_dataset(dataset, exists_ok=True)


def replace_table(
    client: bigquery.Client,
    project_id: str,
    dataset_name: str,
    table_name: str,
    rows: list[dict[str, Any]],
    schema: list[bigquery.SchemaField],
) -> None:
    table_id = f"{project_id}.{dataset_name}.{table_name}"

    client.delete_table(table_id, not_found_ok=True)

    table = bigquery.Table(table_id, schema=schema)
    client.create_table(table)

    if not rows:
        print(f"Created empty table: {table_id}")
        return

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )

    load_job = client.load_table_from_json(
        rows,
        table_id,
        job_config=job_config,
    )
    load_job.result()

    destination = client.get_table(table_id)
    print(f"Loaded {destination.num_rows} rows into {table_id}")


def build_transaction_rows_from_receipts(
    receipts: list[dict[str, Any]],
    run_id: str,
    loaded_at: str,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []

    for receipt in receipts:
        parent_receipt_id = receipt.get("receipt_id")

        for transaction in receipt.get("transactions", []) or []:
            rows.append(
                build_transaction_row(
                    transaction=transaction,
                    parent_receipt_id=parent_receipt_id,
                    run_id=run_id,
                    loaded_at=loaded_at,
                )
            )

    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Land Etsy receipt, transaction, and payment data into BigQuery raw_load."
    )

    parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="Number of recent days to fetch from Etsy.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Number of receipts to request per Etsy API page.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=10,
        help="Maximum number of Etsy receipt pages to fetch.",
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
        help="BigQuery dataset for landing tables.",
    )
    parser.add_argument(
        "--skip-payments",
        action="store_true",
        help="Skip per-receipt payment fetches for quick testing.",
    )

    return parser.parse_args()


def main() -> None:
    load_local_env()
    args = parse_args()

    shop_id = require_env("ETSY_SHOP_ID")

    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    loaded_at = now_timestamp()

    print(f"Starting Etsy orders landing run: {run_id}")
    print(f"Project: {args.project_id}")
    print(f"Dataset: {args.dataset}")
    print(f"Lookback days: {args.days}")

    access_token = refresh_access_token()

    receipts = fetch_receipts(
        access_token=access_token,
        shop_id=shop_id,
        days=args.days,
        limit=args.limit,
        max_pages=args.max_pages,
    )

    receipt_rows = [
        build_receipt_row(receipt, run_id, loaded_at)
        for receipt in receipts
    ]

    transaction_rows = build_transaction_rows_from_receipts(
        receipts=receipts,
        run_id=run_id,
        loaded_at=loaded_at,
    )

    receipt_ids = [
        receipt.get("receipt_id")
        for receipt in receipts
        if receipt.get("receipt_id") is not None
    ]

    payment_rows: list[dict[str, Any]] = []

    if not args.skip_payments:
        payment_rows = fetch_payment_rows(
            access_token=access_token,
            shop_id=shop_id,
            receipt_ids=receipt_ids,
            run_id=run_id,
            loaded_at=loaded_at,
        )

    print(f"Fetched receipts: {len(receipt_rows)}")
    print(f"Flattened transactions: {len(transaction_rows)}")
    print(f"Fetched payments: {len(payment_rows)}")

    client = bigquery.Client(project=args.project_id)

    ensure_dataset(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
    )

    replace_table(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
        table_name=RECEIPTS_TABLE,
        rows=receipt_rows,
        schema=receipt_schema(),
    )

    replace_table(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
        table_name=TRANSACTIONS_TABLE,
        rows=transaction_rows,
        schema=transaction_schema(),
    )

    replace_table(
        client=client,
        project_id=args.project_id,
        dataset_name=args.dataset,
        table_name=PAYMENTS_TABLE,
        rows=payment_rows,
        schema=payment_schema(),
    )

    print("Etsy orders landing run completed successfully.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)