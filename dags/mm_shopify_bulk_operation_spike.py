from __future__ import annotations

import json
import os
import shutil
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from airflow import DAG
from airflow.operators.python import PythonOperator


OUTPUT_DIR = Path("/opt/airflow/local_data/shopify_bulk_spike")

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
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
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

    _write_json("products_bulk_start_response.json", result)

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
            url = bulk_operation.get("url")
            if not url:
                raise RuntimeError(
                    "Bulk operation completed but did not return a result URL: "
                    + json.dumps(bulk_operation, indent=2)
                )

            _write_json("products_bulk_completed_status.json", result)
            return url

        if status in {"FAILED", "CANCELED", "EXPIRED"}:
            _write_json("products_bulk_failed_status.json", result)
            raise RuntimeError(
                "Bulk operation did not complete successfully: "
                + json.dumps(bulk_operation, indent=2)
            )

        time.sleep(sleep_seconds)

    if latest_result:
        _write_json("products_bulk_timeout_status.json", latest_result)

    raise TimeoutError(
        f"Bulk operation did not complete after {max_attempts * sleep_seconds} seconds: "
        f"{operation_id}"
    )


def download_products_bulk_result(**context) -> str:
    result_url = context["ti"].xcom_pull(task_ids="poll_products_bulk_operation")

    if not result_url:
        raise ValueError("Missing result URL from poll_products_bulk_operation")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = OUTPUT_DIR / "products_bulk_result.jsonl"

    request = Request(url=result_url, method="GET")

    with urlopen(request, timeout=300) as response:
        with output_path.open("wb") as output_file:
            shutil.copyfileobj(response, output_file)

    print(f"Downloaded products bulk result to {output_path}")
    return str(output_path)


def inspect_products_bulk_result() -> None:
    input_path = OUTPUT_DIR / "products_bulk_result.jsonl"
    output_path = OUTPUT_DIR / "products_bulk_result_summary.md"

    if not input_path.exists():
        raise FileNotFoundError(f"Missing expected bulk result file: {input_path}")

    total_lines = 0
    sample_records: list[dict] = []
    record_type_counts: dict[str, int] = {}

    with input_path.open("r", encoding="utf-8") as file:
        for line in file:
            total_lines += 1

            if len(sample_records) < 10:
                sample_records.append(json.loads(line))

            record = json.loads(line)
            record_id = str(record.get("id", ""))

            if "/ProductVariant/" in record_id:
                record_type = "ProductVariant"
            elif "/Product/" in record_id:
                record_type = "Product"
            else:
                record_type = "Other"

            record_type_counts[record_type] = record_type_counts.get(record_type, 0) + 1

    lines = [
        "# Shopify Products Bulk Operation Summary",
        "",
        "Generated from local Shopify Bulk Operation JSONL output.",
        "",
        "This file is local scratch output and should not be committed.",
        "",
        f"Total JSONL lines: {total_lines}",
        "",
        "## Record type counts",
        "",
        "```text",
    ]

    for record_type, count in sorted(record_type_counts.items()):
        lines.append(f"{record_type}: {count}")

    lines.extend(
        [
            "```",
            "",
            "## First 10 records",
            "",
            "```json",
            json.dumps(sample_records, indent=2, sort_keys=True),
            "```",
            "",
        ]
    )

    output_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {output_path}")


default_args = {
    "owner": "airflow",
    "retries": 0,
    "retry_delay": timedelta(minutes=2),
}


with DAG(
    dag_id="mm_shopify_bulk_operation_spike",
    description="Spike DAG to test Shopify Bulk Operations JSONL export locally.",
    default_args=default_args,
    start_date=datetime(2026, 4, 28),
    schedule=None,
    catchup=False,
    tags=["mischief-made", "shopify", "api", "bulk", "spike"],
) as dag:
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

    inspect_bulk = PythonOperator(
        task_id="inspect_products_bulk_result",
        python_callable=inspect_products_bulk_result,
    )

    start_bulk >> poll_bulk >> download_bulk >> inspect_bulk