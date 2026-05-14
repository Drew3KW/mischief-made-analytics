from __future__ import annotations

import json
import os
import shutil
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from google.cloud import bigquery


REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = REPO_ROOT / "local_data" / "shopify_api_landing" / "orders"

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "mischief-made-analytics")
LOCATION = os.getenv("BIGQUERY_LOCATION", "US")
RAW_LOAD_DATASET = "raw_load"

ORDERS_TABLE = f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_orders_api_latest"
ORDER_LINE_ITEMS_TABLE = (
    f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_order_line_items_api_latest"
)

BULK_ORDERS_QUERY = """
{
  orders {
    edges {
      node {
        id
        legacyResourceId
        name
        email
        phone
        createdAt
        updatedAt
        processedAt
        cancelledAt
        cancelReason
        displayFinancialStatus
        displayFulfillmentStatus
        currencyCode
        presentmentCurrencyCode
        sourceName
        tags
        currentSubtotalPriceSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        currentShippingPriceSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        currentTotalTaxSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        currentTotalPriceSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        currentTotalDiscountsSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        totalRefundedSet {
          shopMoney {
            amount
            currencyCode
          }
        }
        customer {
          id
          legacyResourceId
          defaultEmailAddress {
            emailAddress
          }
        }
        billingAddress {
          city
          provinceCode
          countryCodeV2
          zip
        }
        shippingAddress {
          city
          provinceCode
          countryCodeV2
          zip
        }
        paymentGatewayNames
        shippingLine {
          title
        }
        lineItems {
          edges {
            node {
              id
              name
              title
              variantTitle
              sku
              vendor
              quantity
              currentQuantity
              requiresShipping
              taxable
              originalUnitPriceSet {
                shopMoney {
                  amount
                  currencyCode
                }
              }
              discountedUnitPriceSet {
                shopMoney {
                  amount
                  currencyCode
                }
              }
              discountedTotalSet {
                shopMoney {
                  amount
                  currencyCode
                }
              }
              totalDiscountSet {
                shopMoney {
                  amount
                  currencyCode
                }
              }
              product {
                id
                legacyResourceId
              }
              variant {
                id
                legacyResourceId
                title
                sku
                barcode
              }
            }
          }
        }
      }
    }
  }
}
"""


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def _normalized_shop_domain() -> str:
    shop_domain = _required_env("SHOPIFY_SHOP_DOMAIN")
    return (
        shop_domain.replace("https://", "")
        .replace("http://", "")
        .strip("/")
    )


def _get_shopify_access_token() -> str:
    shop_domain = _normalized_shop_domain()
    client_id = _required_env("SHOPIFY_API_CLIENT_ID")
    client_secret = _required_env("SHOPIFY_API_CLIENT_SECRET")

    url = f"https://{shop_domain}/admin/oauth/access_token"
    payload = urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }
    ).encode("utf-8")

    request = Request(
        url=url,
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    try:
        with urlopen(request, timeout=60) as response:
            response_body = response.read().decode("utf-8")
            result = json.loads(response_body)
    except HTTPError as exc:
        error_body = exc.read().decode("utf-8")
        raise RuntimeError(
            f"Shopify token request failed with HTTP {exc.code}: {error_body}"
        ) from exc

    access_token = result.get("access_token")
    if not access_token:
        raise RuntimeError(f"Shopify token response did not include access_token: {result}")

    print(
        "Successfully obtained Shopify access token "
        f"with scopes: {result.get('scope', 'unknown')}"
    )
    return access_token


def _shopify_graphql(query: str, variables: dict | None = None) -> dict:
    shop_domain = _normalized_shop_domain()
    api_version = os.getenv("SHOPIFY_ADMIN_API_VERSION", "2026-04")
    access_token = _get_shopify_access_token()

    url = f"https://{shop_domain}/admin/api/{api_version}/graphql.json"
    payload = {
        "query": query,
        "variables": variables or {},
    }

    request = Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Shopify-Access-Token": access_token,
        },
        method="POST",
    )

    try:
        with urlopen(request, timeout=60) as response:
            response_body = response.read().decode("utf-8")
            result = json.loads(response_body)
    except HTTPError as exc:
        error_body = exc.read().decode("utf-8")
        raise RuntimeError(
            f"Shopify GraphQL request failed with HTTP {exc.code}: {error_body}"
        ) from exc

    if "errors" in result:
        raise RuntimeError(
            f"Shopify GraphQL errors: {json.dumps(result['errors'], indent=2)}"
        )

    return result


def _write_json(filename: str, payload: dict) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / filename

    with output_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, indent=2, sort_keys=True)

    print(f"Wrote {output_path}")


def check_landing_output_dir_writeable() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    test_path = OUTPUT_DIR / "_airflow_write_test.txt"
    test_path.write_text("write test\n", encoding="utf-8")
    test_path.unlink()

    print(f"Landing output directory is writeable: {OUTPUT_DIR}")


def _record_type(record: dict) -> str:
    record_id = str(record.get("id", ""))

    if "/LineItem/" in record_id:
        return "LineItem"

    if "/Order/" in record_id:
        return "Order"

    return "Other"


def _read_jsonl_records(input_path: Path) -> list[dict]:
    if not input_path.exists():
        raise FileNotFoundError(f"Missing expected JSONL file: {input_path}")

    records = []

    with input_path.open("r", encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            stripped_line = line.strip()

            if not stripped_line:
                continue

            try:
                records.append(json.loads(stripped_line))
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"Could not parse JSON on line {line_number} of {input_path}"
                ) from exc

    return records


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _json_dumps_or_none(value: object) -> str | None:
    if value is None:
        return None

    return json.dumps(value, sort_keys=True)


def _safe_int(value: object) -> int | None:
    if value is None:
        return None

    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _money_amount(record: dict, field_name: str) -> str | None:
    money_bag = record.get(field_name) or {}
    shop_money = money_bag.get("shopMoney") or {}
    amount = shop_money.get("amount")

    if amount is None:
        return None

    return str(amount)


def _money_currency(record: dict, field_name: str) -> str | None:
    money_bag = record.get(field_name) or {}
    shop_money = money_bag.get("shopMoney") or {}
    return shop_money.get("currencyCode")


def start_orders_bulk_operation() -> str:
    mutation = """
    mutation StartOrdersBulkOperation($query: String!, $groupObjects: Boolean!) {
      bulkOperationRunQuery(query: $query, groupObjects: $groupObjects) {
        bulkOperation {
          id
          status
          createdAt
        }
        userErrors {
          field
          message
        }
      }
    }
    """

    result = _shopify_graphql(
        mutation,
        {
            "query": BULK_ORDERS_QUERY,
            "groupObjects": False,
        },
    )

    payload = result["data"]["bulkOperationRunQuery"]
    user_errors = payload.get("userErrors") or []

    if user_errors:
        raise RuntimeError(
            "Shopify bulkOperationRunQuery returned userErrors: "
            + json.dumps(user_errors, indent=2)
        )

    bulk_operation = payload.get("bulkOperation")

    if not bulk_operation or not bulk_operation.get("id"):
        raise RuntimeError(
            "Shopify bulkOperationRunQuery did not return a bulk operation: "
            + json.dumps(result, indent=2)
        )

    _write_json("orders_landing_bulk_start_response.json", result)

    operation_id = bulk_operation["id"]
    print(f"Started orders bulk operation: {operation_id}")
    return operation_id


def poll_orders_bulk_operation(**context) -> str:
    operation_id = context["ti"].xcom_pull(task_ids="start_orders_bulk_operation")

    if not operation_id:
        raise ValueError("Missing bulk operation ID from start_orders_bulk_operation")

    query = """
    query PollBulkOperation($id: ID!) {
      bulkOperation(id: $id) {
        id
        status
        errorCode
        createdAt
        completedAt
        objectCount
        rootObjectCount
        fileSize
        url
        partialDataUrl
      }
    }
    """

    max_attempts = 120
    sleep_seconds = 10
    latest_result: dict | None = None

    for attempt in range(1, max_attempts + 1):
        result = _shopify_graphql(query, {"id": operation_id})
        latest_result = result

        bulk_operation = result["data"]["bulkOperation"]

        if not bulk_operation:
            raise RuntimeError(f"Bulk operation not found: {operation_id}")

        status = bulk_operation["status"]
        object_count = bulk_operation.get("objectCount")
        root_object_count = bulk_operation.get("rootObjectCount")

        print(
            "Bulk operation poll "
            f"{attempt}/{max_attempts}: status={status}, "
            f"objectCount={object_count}, rootObjectCount={root_object_count}"
        )

        if status == "COMPLETED":
            result_url = bulk_operation.get("url")

            if not result_url:
                raise RuntimeError(
                    "Bulk operation completed but did not return a result URL: "
                    + json.dumps(bulk_operation, indent=2)
                )

            _write_json("orders_landing_bulk_completed_status.json", result)
            return result_url

        if status in {"FAILED", "CANCELED", "EXPIRED"}:
            _write_json("orders_landing_bulk_failed_status.json", result)
            raise RuntimeError(
                "Bulk operation did not complete successfully: "
                + json.dumps(bulk_operation, indent=2)
            )

        time.sleep(sleep_seconds)

    if latest_result:
        _write_json("orders_landing_bulk_timeout_status.json", latest_result)

    raise TimeoutError(
        f"Bulk operation did not complete after {max_attempts * sleep_seconds} seconds: "
        f"{operation_id}"
    )


def download_orders_bulk_result(**context) -> str:
    result_url = context["ti"].xcom_pull(task_ids="poll_orders_bulk_operation")

    if not result_url:
        raise ValueError("Missing result URL from poll_orders_bulk_operation")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "orders_landing_bulk_result.jsonl"

    request = Request(url=result_url, method="GET")

    with urlopen(request, timeout=300) as response:
        with output_path.open("wb") as output_file:
            shutil.copyfileobj(response, output_file)

    print(f"Downloaded orders bulk result to {output_path}")
    return str(output_path)


def load_orders_api_latest(**context) -> int:
    input_path_value = context["ti"].xcom_pull(task_ids="download_orders_bulk_result")

    if not input_path_value:
        raise ValueError("Missing JSONL path from download_orders_bulk_result")

    input_path = Path(input_path_value)
    records = _read_jsonl_records(input_path)
    extracted_at = _now_utc_iso()

    order_rows = []

    for record in records:
        if _record_type(record) != "Order":
            continue

        customer = record.get("customer") or {}
        customer_email = customer.get("defaultEmailAddress") or {}
        billing_address = record.get("billingAddress") or {}
        shipping_address = record.get("shippingAddress") or {}
        shipping_line = record.get("shippingLine") or {}

        order_rows.append(
            {
                "api_extracted_at": extracted_at,
                "shopify_order_graphql_id": record.get("id"),
                "legacy_resource_id": str(record.get("legacyResourceId"))
                if record.get("legacyResourceId") is not None
                else None,
                "order_number": record.get("name"),
                "email": record.get("email"),
                "phone": record.get("phone"),
                "created_at": record.get("createdAt"),
                "updated_at": record.get("updatedAt"),
                "processed_at": record.get("processedAt"),
                "cancelled_at": record.get("cancelledAt"),
                "cancel_reason": record.get("cancelReason"),
                "display_financial_status": record.get("displayFinancialStatus"),
                "display_fulfillment_status": record.get("displayFulfillmentStatus"),
                "currency_code": record.get("currencyCode"),
                "presentment_currency_code": record.get("presentmentCurrencyCode"),
                "order_source": record.get("sourceName"),
                "tags_json": _json_dumps_or_none(record.get("tags") or []),
                "current_subtotal_price": _money_amount(record, "currentSubtotalPriceSet"),
                "current_shipping_price": _money_amount(record, "currentShippingPriceSet"),
                "current_total_tax": _money_amount(record, "currentTotalTaxSet"),
                "current_total_price": _money_amount(record, "currentTotalPriceSet"),
                "current_total_discounts": _money_amount(
                    record,
                    "currentTotalDiscountsSet",
                ),
                "total_refunded": _money_amount(record, "totalRefundedSet"),
                "money_currency_code": _money_currency(record, "currentTotalPriceSet"),
                "customer_graphql_id": customer.get("id"),
                "customer_legacy_resource_id": str(customer.get("legacyResourceId"))
                if customer.get("legacyResourceId") is not None
                else None,
                "customer_email": customer_email.get("emailAddress"),
                "billing_city": billing_address.get("city"),
                "billing_province_code": billing_address.get("provinceCode"),
                "billing_country_code": billing_address.get("countryCodeV2"),
                "billing_zip": billing_address.get("zip"),
                "shipping_city": shipping_address.get("city"),
                "shipping_province_code": shipping_address.get("provinceCode"),
                "shipping_country_code": shipping_address.get("countryCodeV2"),
                "shipping_zip": shipping_address.get("zip"),
                "payment_gateway_names_json": _json_dumps_or_none(
                    record.get("paymentGatewayNames") or []
                ),
                "shipping_line_title": shipping_line.get("title"),
                "raw_record_json": json.dumps(record, sort_keys=True),
            }
        )

    if not order_rows:
        raise ValueError(f"No Order records found in {input_path}")

    schema = [
        bigquery.SchemaField("api_extracted_at", "TIMESTAMP"),
        bigquery.SchemaField("shopify_order_graphql_id", "STRING"),
        bigquery.SchemaField("legacy_resource_id", "STRING"),
        bigquery.SchemaField("order_number", "STRING"),
        bigquery.SchemaField("email", "STRING"),
        bigquery.SchemaField("phone", "STRING"),
        bigquery.SchemaField("created_at", "TIMESTAMP"),
        bigquery.SchemaField("updated_at", "TIMESTAMP"),
        bigquery.SchemaField("processed_at", "TIMESTAMP"),
        bigquery.SchemaField("cancelled_at", "TIMESTAMP"),
        bigquery.SchemaField("cancel_reason", "STRING"),
        bigquery.SchemaField("display_financial_status", "STRING"),
        bigquery.SchemaField("display_fulfillment_status", "STRING"),
        bigquery.SchemaField("currency_code", "STRING"),
        bigquery.SchemaField("presentment_currency_code", "STRING"),
        bigquery.SchemaField("order_source", "STRING"),
        bigquery.SchemaField("tags_json", "STRING"),
        bigquery.SchemaField("current_subtotal_price", "STRING"),
        bigquery.SchemaField("current_shipping_price", "STRING"),
        bigquery.SchemaField("current_total_tax", "STRING"),
        bigquery.SchemaField("current_total_price", "STRING"),
        bigquery.SchemaField("current_total_discounts", "STRING"),
        bigquery.SchemaField("total_refunded", "STRING"),
        bigquery.SchemaField("money_currency_code", "STRING"),
        bigquery.SchemaField("customer_graphql_id", "STRING"),
        bigquery.SchemaField("customer_legacy_resource_id", "STRING"),
        bigquery.SchemaField("customer_email", "STRING"),
        bigquery.SchemaField("billing_city", "STRING"),
        bigquery.SchemaField("billing_province_code", "STRING"),
        bigquery.SchemaField("billing_country_code", "STRING"),
        bigquery.SchemaField("billing_zip", "STRING"),
        bigquery.SchemaField("shipping_city", "STRING"),
        bigquery.SchemaField("shipping_province_code", "STRING"),
        bigquery.SchemaField("shipping_country_code", "STRING"),
        bigquery.SchemaField("shipping_zip", "STRING"),
        bigquery.SchemaField("payment_gateway_names_json", "STRING"),
        bigquery.SchemaField("shipping_line_title", "STRING"),
        bigquery.SchemaField("raw_record_json", "STRING"),
    ]

    client = bigquery.Client(project=PROJECT_ID)
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
    )

    job = client.load_table_from_json(
        order_rows,
        ORDERS_TABLE,
        job_config=job_config,
        location=LOCATION,
    )
    job.result()

    print(f"Loaded {len(order_rows)} Order rows into {ORDERS_TABLE}")
    return len(order_rows)


def load_order_line_items_api_latest(**context) -> int:
    input_path_value = context["ti"].xcom_pull(task_ids="download_orders_bulk_result")

    if not input_path_value:
        raise ValueError("Missing JSONL path from download_orders_bulk_result")

    input_path = Path(input_path_value)
    records = _read_jsonl_records(input_path)
    extracted_at = _now_utc_iso()

    line_item_rows = []

    for record in records:
        if _record_type(record) != "LineItem":
            continue

        product = record.get("product") or {}
        variant = record.get("variant") or {}

        line_item_rows.append(
            {
                "api_extracted_at": extracted_at,
                "shopify_line_item_graphql_id": record.get("id"),
                "shopify_order_graphql_id": record.get("__parentId"),
                "line_item_name": record.get("name"),
                "title": record.get("title"),
                "variant_title": record.get("variantTitle"),
                "sku": record.get("sku"),
                "vendor": record.get("vendor"),
                "quantity": _safe_int(record.get("quantity")),
                "current_quantity": _safe_int(record.get("currentQuantity")),
                "requires_shipping": record.get("requiresShipping"),
                "taxable": record.get("taxable"),
                "original_unit_price": _money_amount(record, "originalUnitPriceSet"),
                "discounted_unit_price": _money_amount(record, "discountedUnitPriceSet"),
                "discounted_total": _money_amount(record, "discountedTotalSet"),
                "total_discount": _money_amount(record, "totalDiscountSet"),
                "money_currency_code": _money_currency(record, "originalUnitPriceSet"),
                "product_graphql_id": product.get("id"),
                "product_legacy_resource_id": str(product.get("legacyResourceId"))
                if product.get("legacyResourceId") is not None
                else None,
                "variant_graphql_id": variant.get("id"),
                "variant_legacy_resource_id": str(variant.get("legacyResourceId"))
                if variant.get("legacyResourceId") is not None
                else None,
                "variant_title_from_variant": variant.get("title"),
                "variant_sku": variant.get("sku"),
                "variant_barcode": variant.get("barcode"),
                "raw_record_json": json.dumps(record, sort_keys=True),
            }
        )

    if not line_item_rows:
        raise ValueError(f"No LineItem records found in {input_path}")

    schema = [
        bigquery.SchemaField("api_extracted_at", "TIMESTAMP"),
        bigquery.SchemaField("shopify_line_item_graphql_id", "STRING"),
        bigquery.SchemaField("shopify_order_graphql_id", "STRING"),
        bigquery.SchemaField("line_item_name", "STRING"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("variant_title", "STRING"),
        bigquery.SchemaField("sku", "STRING"),
        bigquery.SchemaField("vendor", "STRING"),
        bigquery.SchemaField("quantity", "INT64"),
        bigquery.SchemaField("current_quantity", "INT64"),
        bigquery.SchemaField("requires_shipping", "BOOL"),
        bigquery.SchemaField("taxable", "BOOL"),
        bigquery.SchemaField("original_unit_price", "STRING"),
        bigquery.SchemaField("discounted_unit_price", "STRING"),
        bigquery.SchemaField("discounted_total", "STRING"),
        bigquery.SchemaField("total_discount", "STRING"),
        bigquery.SchemaField("money_currency_code", "STRING"),
        bigquery.SchemaField("product_graphql_id", "STRING"),
        bigquery.SchemaField("product_legacy_resource_id", "STRING"),
        bigquery.SchemaField("variant_graphql_id", "STRING"),
        bigquery.SchemaField("variant_legacy_resource_id", "STRING"),
        bigquery.SchemaField("variant_title_from_variant", "STRING"),
        bigquery.SchemaField("variant_sku", "STRING"),
        bigquery.SchemaField("variant_barcode", "STRING"),
        bigquery.SchemaField("raw_record_json", "STRING"),
    ]

    client = bigquery.Client(project=PROJECT_ID)
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
    )

    job = client.load_table_from_json(
        line_item_rows,
        ORDER_LINE_ITEMS_TABLE,
        job_config=job_config,
        location=LOCATION,
    )
    job.result()

    print(f"Loaded {len(line_item_rows)} LineItem rows into {ORDER_LINE_ITEMS_TABLE}")
    return len(line_item_rows)


def validate_orders_api_landing_tables() -> None:
    client = bigquery.Client(project=PROJECT_ID)

    query = f"""
    WITH
      order_counts AS (
        SELECT COUNT(*) AS order_count
        FROM `{ORDERS_TABLE}`
      ),

      line_item_counts AS (
        SELECT COUNT(*) AS line_item_count
        FROM `{ORDER_LINE_ITEMS_TABLE}`
      ),

      duplicate_order_graphql_ids AS (
        SELECT
          COUNT(*) - COUNT(DISTINCT shopify_order_graphql_id)
            AS duplicate_order_graphql_id_count
        FROM `{ORDERS_TABLE}`
      ),

      duplicate_line_item_graphql_ids AS (
        SELECT
          COUNT(*) - COUNT(DISTINCT shopify_line_item_graphql_id)
            AS duplicate_line_item_graphql_id_count
        FROM `{ORDER_LINE_ITEMS_TABLE}`
      ),

      missing_order_numbers AS (
        SELECT COUNT(*) AS missing_order_number_count
        FROM `{ORDERS_TABLE}`
        WHERE order_number IS NULL
      ),

      line_items_missing_parent_id AS (
        SELECT COUNT(*) AS line_items_missing_parent_id_count
        FROM `{ORDER_LINE_ITEMS_TABLE}`
        WHERE shopify_order_graphql_id IS NULL
      ),

      line_item_orphans AS (
        SELECT COUNT(*) AS line_item_orphan_count
        FROM `{ORDER_LINE_ITEMS_TABLE}` AS line_items
        LEFT JOIN `{ORDERS_TABLE}` AS orders
          ON line_items.shopify_order_graphql_id = orders.shopify_order_graphql_id
        WHERE orders.shopify_order_graphql_id IS NULL
      )

    SELECT
      order_count,
      line_item_count,
      duplicate_order_graphql_id_count,
      duplicate_line_item_graphql_id_count,
      missing_order_number_count,
      line_items_missing_parent_id_count,
      line_item_orphan_count
    FROM order_counts
    CROSS JOIN line_item_counts
    CROSS JOIN duplicate_order_graphql_ids
    CROSS JOIN duplicate_line_item_graphql_ids
    CROSS JOIN missing_order_numbers
    CROSS JOIN line_items_missing_parent_id
    CROSS JOIN line_item_orphans
    """

    rows = list(client.query(query, location=LOCATION).result())

    if len(rows) != 1:
        raise RuntimeError("Expected exactly one validation result row.")

    result = dict(rows[0])
    print(f"Orders API landing validation result: {result}")

    if result["order_count"] <= 0:
        raise ValueError("Order landing table has zero rows.")

    if result["line_item_count"] <= 0:
        raise ValueError("Order line item landing table has zero rows.")

    if result["duplicate_order_graphql_id_count"] != 0:
        raise ValueError("Order landing table contains duplicate GraphQL IDs.")

    if result["duplicate_line_item_graphql_id_count"] != 0:
        raise ValueError("Line item landing table contains duplicate GraphQL IDs.")

    if result["missing_order_number_count"] != 0:
        raise ValueError("Order landing table contains missing order numbers.")

    if result["line_items_missing_parent_id_count"] != 0:
        raise ValueError("Line item landing table contains missing parent order IDs.")

    if result["line_item_orphan_count"] != 0:
        raise ValueError("Line item landing table contains orphaned parent order IDs.")


def write_landing_summary(**context) -> None:
    order_count = context["ti"].xcom_pull(task_ids="load_orders_api_latest")
    line_item_count = context["ti"].xcom_pull(
        task_ids="load_order_line_items_api_latest"
    )

    summary_path = OUTPUT_DIR / "orders_api_landing_summary.md"
    lines = [
        "# Shopify Orders API Landing Summary",
        "",
        "Generated from Shopify Bulk Operation JSONL output.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
        "## Landing tables",
        "",
        f"- `{ORDERS_TABLE}`",
        f"- `{ORDER_LINE_ITEMS_TABLE}`",
        "",
        "## Loaded row counts",
        "",
        "```text",
        f"Order: {order_count}",
        f"LineItem: {line_item_count}",
        "```",
        "",
    ]

    summary_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {summary_path}")


DEFAULT_ARGS = {
    "owner": "airflow",
    "retries": 0,
    "retry_delay": timedelta(minutes=2),
}

# Scheduled daily at 20:00 UTC. **scheduling set to none to avoid duplicate API landing runs after implementation of canonical refresh mvp
# This DAG lands Shopify API order and line item data into isolated raw_load tables only.
# It does not rebuild canonical raw tables or refresh downstream business models.
with DAG(
    dag_id="mm_shopify_api_orders_landing_mvp",
    description=(
        "Shopify API orders Bulk Operation landing MVP. "
        "Writes isolated order and line item landing tables in raw_load only."
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 4, 29),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=["mischief-made", "shopify", "api", "bigquery", "orders", "landing", "mvp"],
) as dag:
    check_output_dir = PythonOperator(
        task_id="check_landing_output_dir_writeable",
        python_callable=check_landing_output_dir_writeable,
    )

    start_bulk = PythonOperator(
        task_id="start_orders_bulk_operation",
        python_callable=start_orders_bulk_operation,
    )

    poll_bulk = PythonOperator(
        task_id="poll_orders_bulk_operation",
        python_callable=poll_orders_bulk_operation,
    )

    download_bulk = PythonOperator(
        task_id="download_orders_bulk_result",
        python_callable=download_orders_bulk_result,
    )

    load_orders = PythonOperator(
        task_id="load_orders_api_latest",
        python_callable=load_orders_api_latest,
    )

    load_line_items = PythonOperator(
        task_id="load_order_line_items_api_latest",
        python_callable=load_order_line_items_api_latest,
    )

    validate_landing = PythonOperator(
        task_id="validate_orders_api_landing_tables",
        python_callable=validate_orders_api_landing_tables,
    )

    write_summary = PythonOperator(
        task_id="write_landing_summary",
        python_callable=write_landing_summary,
    )

    check_output_dir >> start_bulk >> poll_bulk >> download_bulk
    download_bulk >> [load_orders, load_line_items]
    [load_orders, load_line_items] >> validate_landing >> write_summary