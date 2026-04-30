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
OUTPUT_DIR = REPO_ROOT / "local_data" / "shopify_api_landing" / "customers"

PROJECT_ID = os.getenv("GCP_PROJECT_ID", "mischief-made-analytics")
LOCATION = os.getenv("BIGQUERY_LOCATION", "US")
RAW_LOAD_DATASET = "raw_load"

CUSTOMERS_TABLE = f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_customers_api_latest"

BULK_CUSTOMERS_QUERY = """
{
  customers {
    edges {
      node {
        id
        legacyResourceId
        firstName
        lastName
        displayName
        state
        verifiedEmail
        taxExempt
        numberOfOrders
        amountSpent {
          amount
          currencyCode
        }
        createdAt
        updatedAt
        tags
        note
        defaultEmailAddress {
          emailAddress
          marketingState
          marketingOptInLevel
          validFormat
        }
        defaultPhoneNumber {
          phoneNumber
          marketingState
          marketingOptInLevel
        }
        defaultAddress {
          company
          address1
          address2
          city
          provinceCode
          countryCodeV2
          zip
          phone
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

    if "/Customer/" in record_id:
        return "Customer"

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


def start_customers_bulk_operation() -> str:
    mutation = """
    mutation StartCustomersBulkOperation($query: String!, $groupObjects: Boolean!) {
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
            "query": BULK_CUSTOMERS_QUERY,
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

    _write_json("customers_landing_bulk_start_response.json", result)

    operation_id = bulk_operation["id"]
    print(f"Started customers bulk operation: {operation_id}")
    return operation_id


def poll_customers_bulk_operation(**context) -> str:
    operation_id = context["ti"].xcom_pull(task_ids="start_customers_bulk_operation")

    if not operation_id:
        raise ValueError("Missing bulk operation ID from start_customers_bulk_operation")

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

            _write_json("customers_landing_bulk_completed_status.json", result)
            return result_url

        if status in {"FAILED", "CANCELED", "EXPIRED"}:
            _write_json("customers_landing_bulk_failed_status.json", result)
            raise RuntimeError(
                "Bulk operation did not complete successfully: "
                + json.dumps(bulk_operation, indent=2)
            )

        time.sleep(sleep_seconds)

    if latest_result:
        _write_json("customers_landing_bulk_timeout_status.json", latest_result)

    raise TimeoutError(
        f"Bulk operation did not complete after {max_attempts * sleep_seconds} seconds: "
        f"{operation_id}"
    )


def download_customers_bulk_result(**context) -> str:
    result_url = context["ti"].xcom_pull(task_ids="poll_customers_bulk_operation")

    if not result_url:
        raise ValueError("Missing result URL from poll_customers_bulk_operation")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "customers_landing_bulk_result.jsonl"

    request = Request(url=result_url, method="GET")

    with urlopen(request, timeout=300) as response:
        with output_path.open("wb") as output_file:
            shutil.copyfileobj(response, output_file)

    print(f"Downloaded customers bulk result to {output_path}")
    return str(output_path)


def load_customers_api_latest(**context) -> int:
    input_path_value = context["ti"].xcom_pull(task_ids="download_customers_bulk_result")

    if not input_path_value:
        raise ValueError("Missing JSONL path from download_customers_bulk_result")

    input_path = Path(input_path_value)
    records = _read_jsonl_records(input_path)
    extracted_at = _now_utc_iso()

    customer_rows = []

    for record in records:
        if _record_type(record) != "Customer":
            continue

        amount_spent = record.get("amountSpent") or {}
        default_email = record.get("defaultEmailAddress") or {}
        default_phone = record.get("defaultPhoneNumber") or {}
        default_address = record.get("defaultAddress") or {}

        customer_rows.append(
            {
                "api_extracted_at": extracted_at,
                "shopify_customer_graphql_id": record.get("id"),
                "legacy_resource_id": str(record.get("legacyResourceId"))
                if record.get("legacyResourceId") is not None
                else None,
                "email": default_email.get("emailAddress"),
                "email_marketing_state": default_email.get("marketingState"),
                "email_marketing_opt_in_level": default_email.get("marketingOptInLevel"),
                "email_valid_format": default_email.get("validFormat"),
                "first_name": record.get("firstName"),
                "last_name": record.get("lastName"),
                "display_name": record.get("displayName"),
                "phone": default_phone.get("phoneNumber"),
                "sms_marketing_state": default_phone.get("marketingState"),
                "sms_marketing_opt_in_level": default_phone.get("marketingOptInLevel"),
                "state": record.get("state"),
                "verified_email": record.get("verifiedEmail"),
                "tax_exempt": record.get("taxExempt"),
                "number_of_orders": _safe_int(record.get("numberOfOrders")),
                "amount_spent": str(amount_spent.get("amount"))
                if amount_spent.get("amount") is not None
                else None,
                "amount_spent_currency": amount_spent.get("currencyCode"),
                "created_at": record.get("createdAt"),
                "updated_at": record.get("updatedAt"),
                "note": record.get("note"),
                "tags_json": _json_dumps_or_none(record.get("tags") or []),
                "default_address_company": default_address.get("company"),
                "default_address_address1": default_address.get("address1"),
                "default_address_address2": default_address.get("address2"),
                "default_address_city": default_address.get("city"),
                "default_address_province_code": default_address.get("provinceCode"),
                "default_address_country_code": default_address.get("countryCodeV2"),
                "default_address_zip": default_address.get("zip"),
                "default_address_phone": default_address.get("phone"),
                "default_address_json": _json_dumps_or_none(record.get("defaultAddress")),
                "raw_record_json": json.dumps(record, sort_keys=True),
            }
        )

    if not customer_rows:
        raise ValueError(f"No Customer records found in {input_path}")

    schema = [
        bigquery.SchemaField("api_extracted_at", "TIMESTAMP"),
        bigquery.SchemaField("shopify_customer_graphql_id", "STRING"),
        bigquery.SchemaField("legacy_resource_id", "STRING"),
        bigquery.SchemaField("email", "STRING"),
        bigquery.SchemaField("email_marketing_state", "STRING"),
        bigquery.SchemaField("email_marketing_opt_in_level", "STRING"),
        bigquery.SchemaField("email_valid_format", "BOOL"),
        bigquery.SchemaField("first_name", "STRING"),
        bigquery.SchemaField("last_name", "STRING"),
        bigquery.SchemaField("display_name", "STRING"),
        bigquery.SchemaField("phone", "STRING"),
        bigquery.SchemaField("sms_marketing_state", "STRING"),
        bigquery.SchemaField("sms_marketing_opt_in_level", "STRING"),
        bigquery.SchemaField("state", "STRING"),
        bigquery.SchemaField("verified_email", "BOOL"),
        bigquery.SchemaField("tax_exempt", "BOOL"),
        bigquery.SchemaField("number_of_orders", "INT64"),
        bigquery.SchemaField("amount_spent", "STRING"),
        bigquery.SchemaField("amount_spent_currency", "STRING"),
        bigquery.SchemaField("created_at", "TIMESTAMP"),
        bigquery.SchemaField("updated_at", "TIMESTAMP"),
        bigquery.SchemaField("note", "STRING"),
        bigquery.SchemaField("tags_json", "STRING"),
        bigquery.SchemaField("default_address_company", "STRING"),
        bigquery.SchemaField("default_address_address1", "STRING"),
        bigquery.SchemaField("default_address_address2", "STRING"),
        bigquery.SchemaField("default_address_city", "STRING"),
        bigquery.SchemaField("default_address_province_code", "STRING"),
        bigquery.SchemaField("default_address_country_code", "STRING"),
        bigquery.SchemaField("default_address_zip", "STRING"),
        bigquery.SchemaField("default_address_phone", "STRING"),
        bigquery.SchemaField("default_address_json", "STRING"),
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
        customer_rows,
        CUSTOMERS_TABLE,
        job_config=job_config,
        location=LOCATION,
    )
    job.result()

    print(f"Loaded {len(customer_rows)} Customer rows into {CUSTOMERS_TABLE}")
    return len(customer_rows)


def validate_customers_api_landing_table() -> None:
    client = bigquery.Client(project=PROJECT_ID)

    query = f"""
    WITH
      customer_counts AS (
        SELECT COUNT(*) AS customer_count
        FROM `{CUSTOMERS_TABLE}`
      ),

      duplicate_graphql_ids AS (
        SELECT
          COUNT(*) - COUNT(DISTINCT shopify_customer_graphql_id)
            AS duplicate_graphql_id_count
        FROM `{CUSTOMERS_TABLE}`
      ),

      duplicate_legacy_resource_ids AS (
        SELECT
          COUNT(*) - COUNT(DISTINCT legacy_resource_id)
            AS duplicate_legacy_resource_id_count
        FROM `{CUSTOMERS_TABLE}`
        WHERE legacy_resource_id IS NOT NULL
      ),

      missing_legacy_resource_ids AS (
        SELECT COUNT(*) AS missing_legacy_resource_id_count
        FROM `{CUSTOMERS_TABLE}`
        WHERE legacy_resource_id IS NULL
      )

    SELECT
      customer_count,
      duplicate_graphql_id_count,
      duplicate_legacy_resource_id_count,
      missing_legacy_resource_id_count
    FROM customer_counts
    CROSS JOIN duplicate_graphql_ids
    CROSS JOIN duplicate_legacy_resource_ids
    CROSS JOIN missing_legacy_resource_ids
    """

    rows = list(client.query(query, location=LOCATION).result())

    if len(rows) != 1:
        raise RuntimeError("Expected exactly one validation result row.")

    result = dict(rows[0])
    print(f"Customers API landing validation result: {result}")

    if result["customer_count"] <= 0:
        raise ValueError("Customer landing table has zero rows.")

    if result["duplicate_graphql_id_count"] != 0:
        raise ValueError("Customer landing table contains duplicate GraphQL IDs.")

    if result["duplicate_legacy_resource_id_count"] != 0:
        raise ValueError("Customer landing table contains duplicate legacy resource IDs.")

    if result["missing_legacy_resource_id_count"] != 0:
        raise ValueError("Customer landing table contains missing legacy resource IDs.")


def write_landing_summary(**context) -> None:
    customer_count = context["ti"].xcom_pull(task_ids="load_customers_api_latest")

    summary_path = OUTPUT_DIR / "customers_api_landing_summary.md"
    lines = [
        "# Shopify Customers API Landing Summary",
        "",
        "Generated from Shopify Bulk Operation JSONL output.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
        "## Landing table",
        "",
        f"- `{CUSTOMERS_TABLE}`",
        "",
        "## Loaded row counts",
        "",
        "```text",
        f"Customer: {customer_count}",
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

# Scheduled daily at 20:30 UTC.
# This DAG lands Shopify API customer data into an isolated raw_load table only.
# It does not rebuild canonical raw tables or refresh downstream business models.
with DAG(
    dag_id="mm_shopify_api_customers_landing_mvp",
    description=(
        "Shopify API customers Bulk Operation landing MVP. "
        "Writes isolated customer landing table in raw_load only."
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 4, 29),
    schedule="30 20 * * *",
    catchup=False,
    max_active_runs=1,
    tags=["mischief-made", "shopify", "api", "bigquery", "customers", "landing", "mvp"],
) as dag:
    check_output_dir = PythonOperator(
        task_id="check_landing_output_dir_writeable",
        python_callable=check_landing_output_dir_writeable,
    )

    start_bulk = PythonOperator(
        task_id="start_customers_bulk_operation",
        python_callable=start_customers_bulk_operation,
    )

    poll_bulk = PythonOperator(
        task_id="poll_customers_bulk_operation",
        python_callable=poll_customers_bulk_operation,
    )

    download_bulk = PythonOperator(
        task_id="download_customers_bulk_result",
        python_callable=download_customers_bulk_result,
    )

    load_customers = PythonOperator(
        task_id="load_customers_api_latest",
        python_callable=load_customers_api_latest,
    )

    validate_landing = PythonOperator(
        task_id="validate_customers_api_landing_table",
        python_callable=validate_customers_api_landing_table,
    )

    write_summary = PythonOperator(
        task_id="write_landing_summary",
        python_callable=write_landing_summary,
    )

    check_output_dir >> start_bulk >> poll_bulk >> download_bulk
    download_bulk >> load_customers >> validate_landing >> write_summary