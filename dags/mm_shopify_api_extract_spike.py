from __future__ import annotations

import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from airflow import DAG
from airflow.operators.python import PythonOperator


OUTPUT_DIR = Path("/opt/airflow/local_data/shopify_api_spike")


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


def test_shopify_connection() -> None:
    query = """
    query ShopInfo {
      shop {
        name
        myshopifyDomain
        primaryDomain {
          host
          url
        }
      }
    }
    """

    result = _shopify_graphql(query)
    _write_json("shop_connection_test.json", result)


def extract_orders_sample() -> None:
    query = """
    query OrdersSample($first: Int!) {
      orders(first: $first, sortKey: CREATED_AT, reverse: true) {
        edges {
          cursor
          node {
            id
            name
            createdAt
            updatedAt
            processedAt
            cancelledAt
            displayFinancialStatus
            displayFulfillmentStatus
            email
            customer {
              id
              email
              displayName
            }
            lineItems(first: 5) {
              edges {
                node {
                  id
                  title
                  quantity
                  sku
                  variant {
                    id
                    sku
                    title
                    product {
                      id
                      title
                      handle
                    }
                  }
                }
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """

    result = _shopify_graphql(query, {"first": 5})
    _write_json("orders_sample.json", result)


def extract_products_sample() -> None:
    query = """
    query ProductsSample($first: Int!) {
      products(first: $first, sortKey: UPDATED_AT, reverse: true) {
        edges {
          cursor
          node {
            id
            title
            handle
            vendor
            productType
            status
            createdAt
            updatedAt
            tags
            variants(first: 5) {
              edges {
                node {
                  id
                  title
                  sku
                  price
                  inventoryQuantity
                  selectedOptions {
                    name
                    value
                  }
                }
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """

    result = _shopify_graphql(query, {"first": 5})
    _write_json("products_sample.json", result)


def extract_customers_sample() -> None:
    query = """
    query CustomersSample($first: Int!) {
      customers(first: $first, sortKey: UPDATED_AT, reverse: true) {
        edges {
          cursor
          node {
            id
            email
            firstName
            lastName
            displayName
            createdAt
            updatedAt
            numberOfOrders
            defaultAddress {
              city
              province
              country
              zip
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """

    result = _shopify_graphql(query, {"first": 5})
    _write_json("customers_sample.json", result)


default_args = {
    "owner": "airflow",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}


with DAG(
    dag_id="mm_shopify_api_extract_spike",
    description="Spike DAG to test Shopify Admin GraphQL API extraction into local JSON files.",
    default_args=default_args,
    start_date=datetime(2026, 4, 27),
    schedule=None,
    catchup=False,
    tags=["mischief-made", "shopify", "api", "spike"],
) as dag:
    test_connection = PythonOperator(
        task_id="test_shopify_connection",
        python_callable=test_shopify_connection,
    )

    orders_sample = PythonOperator(
        task_id="extract_orders_sample",
        python_callable=extract_orders_sample,
    )

    products_sample = PythonOperator(
        task_id="extract_products_sample",
        python_callable=extract_products_sample,
    )

    customers_sample = PythonOperator(
        task_id="extract_customers_sample",
        python_callable=extract_customers_sample,
    )

    test_connection >> [orders_sample, products_sample, customers_sample]