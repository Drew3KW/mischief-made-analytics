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
OUTPUT_DIR = REPO_ROOT / "local_data" / "shopify_api_landing"

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "mischief-made-analytics")
LOCATION = os.getenv("BIGQUERY_LOCATION", "US")
RAW_LOAD_DATASET = "raw_load"

PRODUCTS_TABLE = f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_products_api_latest"
VARIANTS_TABLE = f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_product_variants_api_latest"

BULK_PRODUCTS_QUERY = """
{
  products {
    edges {
      node {
        id
        legacyResourceId
        title
        handle
        vendor
        productType
        status
        createdAt
        updatedAt
        tags
        variants {
          edges {
            node {
              id
              legacyResourceId
              title
              sku
              barcode
              price
              compareAtPrice
              taxable
              inventoryQuantity
              selectedOptions {
                name
                value
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

    if "/ProductVariant/" in record_id:
        return "ProductVariant"

    if "/Product/" in record_id:
        return "Product"

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


def start_products_bulk_operation() -> str:
    mutation = """
    mutation StartProductsBulkOperation($query: String!, $groupObjects: Boolean!) {
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
            "query": BULK_PRODUCTS_QUERY,
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

    _write_json("products_landing_bulk_start_response.json", result)

    operation_id = bulk_operation["id"]
    print(f"Started products bulk operation: {operation_id}")
    return operation_id


def poll_products_bulk_operation(**context) -> str:
    operation_id = context["ti"].xcom_pull(task_ids="start_products_bulk_operation")

    if not operation_id:
        raise ValueError("Missing bulk operation ID from start_products_bulk_operation")

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

    max_attempts = 60
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

            _write_json("products_landing_bulk_completed_status.json", result)
            return result_url

        if status in {"FAILED", "CANCELED", "EXPIRED"}:
            _write_json("products_landing_bulk_failed_status.json", result)
            raise RuntimeError(
                "Bulk operation did not complete successfully: "
                + json.dumps(bulk_operation, indent=2)
            )

        time.sleep(sleep_seconds)

    if latest_result:
        _write_json("products_landing_bulk_timeout_status.json", latest_result)

    raise TimeoutError(
        f"Bulk operation did not complete after {max_attempts * sleep_seconds} seconds: "
        f"{operation_id}"
    )


def download_products_bulk_result(**context) -> str:
    result_url = context["ti"].xcom_pull(task_ids="poll_products_bulk_operation")

    if not result_url:
        raise ValueError("Missing result URL from poll_products_bulk_operation")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "products_landing_bulk_result.jsonl"

    request = Request(url=result_url, method="GET")

    with urlopen(request, timeout=300) as response:
        with output_path.open("wb") as output_file:
            shutil.copyfileobj(response, output_file)

    print(f"Downloaded products bulk result to {output_path}")
    return str(output_path)


def load_products_api_latest(**context) -> int:
    input_path_value = context["ti"].xcom_pull(task_ids="download_products_bulk_result")

    if not input_path_value:
        raise ValueError("Missing JSONL path from download_products_bulk_result")

    input_path = Path(input_path_value)
    records = _read_jsonl_records(input_path)
    extracted_at = _now_utc_iso()

    product_rows = []

    for record in records:
        if _record_type(record) != "Product":
            continue

        product_rows.append(
            {
                "api_extracted_at": extracted_at,
                "shopify_product_graphql_id": record.get("id"),
                "legacy_resource_id": record.get("legacyResourceId"),
                "title": record.get("title"),
                "handle": record.get("handle"),
                "vendor": record.get("vendor"),
                "product_type": record.get("productType"),
                "status": record.get("status"),
                "created_at": record.get("createdAt"),
                "updated_at": record.get("updatedAt"),
                "tags_json": json.dumps(record.get("tags") or [], sort_keys=True),
                "raw_record_json": json.dumps(record, sort_keys=True),
            }
        )

    if not product_rows:
        raise ValueError(f"No Product records found in {input_path}")

    schema = [
        bigquery.SchemaField("api_extracted_at", "TIMESTAMP"),
        bigquery.SchemaField("shopify_product_graphql_id", "STRING"),
        bigquery.SchemaField("legacy_resource_id", "STRING"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("handle", "STRING"),
        bigquery.SchemaField("vendor", "STRING"),
        bigquery.SchemaField("product_type", "STRING"),
        bigquery.SchemaField("status", "STRING"),
        bigquery.SchemaField("created_at", "TIMESTAMP"),
        bigquery.SchemaField("updated_at", "TIMESTAMP"),
        bigquery.SchemaField("tags_json", "STRING"),
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
        product_rows,
        PRODUCTS_TABLE,
        job_config=job_config,
        location=LOCATION,
    )
    job.result()

    print(f"Loaded {len(product_rows)} Product rows into {PRODUCTS_TABLE}")
    return len(product_rows)


def load_product_variants_api_latest(**context) -> int:
    input_path_value = context["ti"].xcom_pull(task_ids="download_products_bulk_result")

    if not input_path_value:
        raise ValueError("Missing JSONL path from download_products_bulk_result")

    input_path = Path(input_path_value)
    records = _read_jsonl_records(input_path)
    extracted_at = _now_utc_iso()

    variant_rows = []

    for record in records:
        if _record_type(record) != "ProductVariant":
            continue

        variant_rows.append(
            {
                "api_extracted_at": extracted_at,
                "shopify_product_variant_graphql_id": record.get("id"),
                "shopify_product_graphql_id": record.get("__parentId"),
                "legacy_resource_id": record.get("legacyResourceId"),
                "title": record.get("title"),
                "sku": record.get("sku"),
                "barcode": record.get("barcode"),
                "price": record.get("price"),
                "compare_at_price": record.get("compareAtPrice"),
                "taxable": record.get("taxable"),
                "inventory_quantity": record.get("inventoryQuantity"),
                "selected_options_json": json.dumps(
                    record.get("selectedOptions") or [],
                    sort_keys=True,
                ),
                "raw_record_json": json.dumps(record, sort_keys=True),
            }
        )

    if not variant_rows:
        raise ValueError(f"No ProductVariant records found in {input_path}")

    schema = [
        bigquery.SchemaField("api_extracted_at", "TIMESTAMP"),
        bigquery.SchemaField("shopify_product_variant_graphql_id", "STRING"),
        bigquery.SchemaField("shopify_product_graphql_id", "STRING"),
        bigquery.SchemaField("legacy_resource_id", "STRING"),
        bigquery.SchemaField("title", "STRING"),
        bigquery.SchemaField("sku", "STRING"),
        bigquery.SchemaField("barcode", "STRING"),
        bigquery.SchemaField("price", "STRING"),
        bigquery.SchemaField("compare_at_price", "STRING"),
        bigquery.SchemaField("taxable", "BOOL"),
        bigquery.SchemaField("inventory_quantity", "INT64"),
        bigquery.SchemaField("selected_options_json", "STRING"),
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
        variant_rows,
        VARIANTS_TABLE,
        job_config=job_config,
        location=LOCATION,
    )
    job.result()

    print(f"Loaded {len(variant_rows)} ProductVariant rows into {VARIANTS_TABLE}")
    return len(variant_rows)


def validate_api_landing_tables() -> None:
    client = bigquery.Client(project=PROJECT_ID)

    query = f"""
    WITH
      product_counts AS (
        SELECT COUNT(*) AS product_count
        FROM `{PRODUCTS_TABLE}`
      ),

      variant_counts AS (
        SELECT COUNT(*) AS variant_count
        FROM `{VARIANTS_TABLE}`
      ),

      variants_missing_parent_id AS (
        SELECT COUNT(*) AS variant_missing_parent_id_count
        FROM `{VARIANTS_TABLE}`
        WHERE shopify_product_graphql_id IS NULL
      ),

      variant_orphans AS (
        SELECT COUNT(*) AS variant_orphan_count
        FROM `{VARIANTS_TABLE}` AS variants
        LEFT JOIN `{PRODUCTS_TABLE}` AS products
          ON variants.shopify_product_graphql_id = products.shopify_product_graphql_id
        WHERE products.shopify_product_graphql_id IS NULL
      )

    SELECT
      product_count,
      variant_count,
      variant_missing_parent_id_count,
      variant_orphan_count
    FROM product_counts
    CROSS JOIN variant_counts
    CROSS JOIN variants_missing_parent_id
    CROSS JOIN variant_orphans
    """

    rows = list(client.query(query, location=LOCATION).result())

    if len(rows) != 1:
        raise RuntimeError("Expected exactly one validation result row.")

    result = dict(rows[0])
    print(f"API landing validation result: {result}")

    if result["product_count"] <= 0:
        raise ValueError("Product landing table has zero rows.")

    if result["variant_count"] <= 0:
        raise ValueError("Product variant landing table has zero rows.")

    if result["variant_missing_parent_id_count"] != 0:
        raise ValueError(
            "Product variant landing table contains variants with missing parent IDs."
        )

    if result["variant_orphan_count"] != 0:
        raise ValueError(
            "Product variant landing table contains variants whose parent product "
            "is missing from the product landing table."
        )


def write_landing_summary(**context) -> None:
    product_count = context["ti"].xcom_pull(task_ids="load_products_api_latest")
    variant_count = context["ti"].xcom_pull(task_ids="load_product_variants_api_latest")

    summary_path = OUTPUT_DIR / "products_api_landing_summary.md"
    lines = [
        "# Shopify Products API Landing Summary",
        "",
        "Generated from Shopify Bulk Operation JSONL output.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
        "## Landing tables",
        "",
        f"- `{PRODUCTS_TABLE}`",
        f"- `{VARIANTS_TABLE}`",
        "",
        "## Loaded row counts",
        "",
        "```text",
        f"Product: {product_count}",
        f"ProductVariant: {variant_count}",
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


with DAG(
    dag_id="mm_shopify_api_products_landing_mvp",
    description=(
        "Shopify API products Bulk Operation landing MVP. "
        "Writes isolated product and variant landing tables in raw_load only."
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 4, 28),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=["mischief-made", "shopify", "api", "bigquery", "landing", "mvp"],
) as dag:
    check_output_dir = PythonOperator(
        task_id="check_landing_output_dir_writeable",
        python_callable=check_landing_output_dir_writeable,
    )
    
    start_bulk = PythonOperator(
        task_id="start_products_bulk_operation",
        python_callable=start_products_bulk_operation,
    )

    poll_bulk = PythonOperator(
        task_id="poll_products_bulk_operation",
        python_callable=poll_products_bulk_operation,
    )

    download_bulk = PythonOperator(
        task_id="download_products_bulk_result",
        python_callable=download_products_bulk_result,
    )

    load_products = PythonOperator(
        task_id="load_products_api_latest",
        python_callable=load_products_api_latest,
    )

    load_variants = PythonOperator(
        task_id="load_product_variants_api_latest",
        python_callable=load_product_variants_api_latest,
    )

    validate_landing = PythonOperator(
        task_id="validate_api_landing_tables",
        python_callable=validate_api_landing_tables,
    )

    write_summary = PythonOperator(
        task_id="write_landing_summary",
        python_callable=write_landing_summary,
    )

    check_output_dir >> start_bulk >> poll_bulk >> download_bulk
    download_bulk >> [load_products, load_variants]
    [load_products, load_variants] >> validate_landing >> write_summary