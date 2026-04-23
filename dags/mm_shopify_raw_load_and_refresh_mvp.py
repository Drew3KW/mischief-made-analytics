from __future__ import annotations

import csv
import re
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.sdk import TaskGroup
from google.cloud import bigquery


# Repo root = parent of the dags/ folder
REPO_ROOT = Path(__file__).resolve().parents[1]

# Local folder for manual Shopify CSV drops
LOCAL_SHOPIFY_DIR = REPO_ROOT / "local_data" / "shopify"

DEFAULT_ARGS = {
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}

GCP_CONN_ID = "google_cloud_default"
PROJECT_ID = "mischief-made-analytics"
LOCATION = "US"

RAW_LOAD_DATASET = "raw_load"
RAW_DATASET = "raw"


def build_bq_sql_task(
    *,
    task_id: str,
    sql_relative_path: str,
    gcp_conn_id: str = GCP_CONN_ID,
    project_id: str = PROJECT_ID,
    location: str = LOCATION,
) -> BigQueryInsertJobOperator:
    sql_path = REPO_ROOT / sql_relative_path

    return BigQueryInsertJobOperator(
        task_id=task_id,
        gcp_conn_id=gcp_conn_id,
        project_id=project_id,
        location=location,
        configuration={
            "query": {
                "query": sql_path.read_text(),
                "useLegacySql": False,
            }
        },
    )


def sanitize_column_name(column_name: str) -> str:
    """
    Convert Shopify CSV headers into BigQuery-friendly snake_case field names.

    Examples:
    - Body (HTML) -> body_html
    - Variant SKU -> variant_sku
    - Default Address Address1 -> default_address_address1
    """
    sanitized = column_name.strip().lower()
    sanitized = re.sub(r"[^a-z0-9]+", "_", sanitized)
    sanitized = re.sub(r"_+", "_", sanitized)
    sanitized = sanitized.strip("_")

    if not sanitized:
        raise ValueError(f"Could not sanitize empty/invalid column name: {column_name!r}")

    if sanitized[0].isdigit():
        sanitized = f"col_{sanitized}"

    return sanitized


def read_csv_headers(csv_path: Path) -> list[str]:
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.reader(handle)
        headers = next(reader)

    if not headers:
        raise ValueError(f"No header row found in {csv_path}")

    return headers


def build_all_string_schema(
    csv_path: Path,
    *,
    preserve_headers: bool,
) -> list[bigquery.SchemaField]:
    headers = read_csv_headers(csv_path)

    if preserve_headers:
        field_names = headers
    else:
        field_names = [sanitize_column_name(header) for header in headers]

    return [bigquery.SchemaField(name, "STRING") for name in field_names]


def ensure_file_exists(csv_path: Path) -> None:
    if not csv_path.exists():
        raise FileNotFoundError(f"Required input file not found: {csv_path}")

    if not csv_path.is_file():
        raise ValueError(f"Input path is not a file: {csv_path}")

    if csv_path.stat().st_size == 0:
        raise ValueError(f"Input file is empty: {csv_path}")


def check_input_files() -> None:
    """
    Fail early if the required local CSV files are missing or empty.
    """
    required_files = [
        LOCAL_SHOPIFY_DIR / "customers.csv",
        LOCAL_SHOPIFY_DIR / "products.csv",
        LOCAL_SHOPIFY_DIR / "orders.csv",
    ]

    for csv_path in required_files:
        ensure_file_exists(csv_path)


def load_csv_to_bigquery(
    *,
    csv_path: Path,
    destination_table: str,
    preserve_headers: bool,
    allow_quoted_newlines: bool = False,
) -> None:
    """
    Load a local Shopify CSV into a BigQuery landing table.

    Design choices:
    - manual schema
    - all STRING fields
    - WRITE_TRUNCATE for the landing table only
    - header row skipped in file load
    """
    client = bigquery.Client(project=PROJECT_ID)

    schema = build_all_string_schema(
        csv_path,
        preserve_headers=preserve_headers,
    )

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        field_delimiter=",",
        quote_character='"',
        encoding="UTF-8",
        allow_quoted_newlines=allow_quoted_newlines,
    )

    with csv_path.open("rb") as handle:
        job = client.load_table_from_file(
            handle,
            destination=destination_table,
            job_config=job_config,
            location=LOCATION,
        )

    job.result()


def load_customers_csv() -> None:
    load_csv_to_bigquery(
        csv_path=LOCAL_SHOPIFY_DIR / "customers.csv",
        destination_table=f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_customers_latest",
        preserve_headers=False,
        allow_quoted_newlines=True,
    )


def load_products_csv() -> None:
    load_csv_to_bigquery(
        csv_path=LOCAL_SHOPIFY_DIR / "products.csv",
        destination_table=f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_products_latest",
        preserve_headers=False,
        allow_quoted_newlines=True,
    )


def load_orders_csv() -> None:
    load_csv_to_bigquery(
        csv_path=LOCAL_SHOPIFY_DIR / "orders.csv",
        destination_table=f"{PROJECT_ID}.{RAW_LOAD_DATASET}.shopify_orders_latest",
        preserve_headers=True,
        allow_quoted_newlines=True,
    )


with DAG(
    dag_id="mm_shopify_raw_load_and_refresh_mvp",
    description="Manual MVP Shopify CSV raw load plus warehouse refresh in BigQuery.",
    start_date=datetime(2026, 4, 22),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["mischief-made", "shopify", "bigquery", "airflow", "portfolio", "mvp"],
) as dag:
    file_checks = PythonOperator(
        task_id="check_input_files",
        python_callable=check_input_files,
    )

    with TaskGroup(group_id="raw_load") as raw_load:
        load_raw_customers = PythonOperator(
            task_id="load_raw_customers_csv",
            python_callable=load_customers_csv,
        )

        load_raw_products = PythonOperator(
            task_id="load_raw_products_csv",
            python_callable=load_products_csv,
        )

        load_raw_orders = PythonOperator(
            task_id="load_raw_orders_csv",
            python_callable=load_orders_csv,
        )

        load_raw_customers >> load_raw_products >> load_raw_orders

    with TaskGroup(group_id="raw_rebuild") as raw_rebuild:
        rebuild_shopify_customers = build_bq_sql_task(
            task_id="rebuild_shopify_customers",
            sql_relative_path="sql/raw/rebuild_shopify_customers.sql",
        )

        rebuild_shopify_products = build_bq_sql_task(
            task_id="rebuild_shopify_products",
            sql_relative_path="sql/raw/rebuild_shopify_products.sql",
        )

        rebuild_shopify_orders = build_bq_sql_task(
            task_id="rebuild_shopify_orders",
            sql_relative_path="sql/raw/rebuild_shopify_orders.sql",
        )

        rebuild_shopify_customers >> rebuild_shopify_products >> rebuild_shopify_orders

    with TaskGroup(group_id="staging") as staging:
        stg_shopify_customers = build_bq_sql_task(
            task_id="stg_shopify_customers",
            sql_relative_path="sql/staging/stg_shopify_customers.sql",
        )

        stg_shopify_orders = build_bq_sql_task(
            task_id="stg_shopify_orders",
            sql_relative_path="sql/staging/stg_shopify_orders.sql",
        )

        stg_shopify_order_items = build_bq_sql_task(
            task_id="stg_shopify_order_items",
            sql_relative_path="sql/staging/stg_shopify_order_items.sql",
        )

        stg_shopify_products = build_bq_sql_task(
            task_id="stg_shopify_products",
            sql_relative_path="sql/staging/stg_shopify_products.sql",
        )

    with TaskGroup(group_id="marts") as marts:
        dim_products_historical = build_bq_sql_task(
            task_id="dim_products_historical",
            sql_relative_path="sql/marts/dim_products_historical.sql",
        )

        dim_products = build_bq_sql_task(
            task_id="dim_products",
            sql_relative_path="sql/marts/dim_products.sql",
        )

        product_family_map = build_bq_sql_task(
            task_id="product_family_map",
            sql_relative_path="sql/marts/product_family_map.sql",
        )

        dim_product_families = build_bq_sql_task(
            task_id="dim_product_families",
            sql_relative_path="sql/marts/dim_product_families.sql",
        )

        dim_customers = build_bq_sql_task(
            task_id="dim_customers",
            sql_relative_path="sql/marts/dim_customers.sql",
        )

        fct_orders = build_bq_sql_task(
            task_id="fct_orders",
            sql_relative_path="sql/marts/fct_orders.sql",
        )

        fct_order_items = build_bq_sql_task(
            task_id="fct_order_items",
            sql_relative_path="sql/marts/fct_order_items.sql",
        )

        dim_products_historical >> dim_products
        dim_products >> product_family_map >> dim_product_families
        dim_customers >> fct_orders >> fct_order_items
        dim_product_families >> fct_order_items
        dim_products >> fct_order_items

    with TaskGroup(group_id="analysis") as analysis:
        anl_product_performance_by_family = build_bq_sql_task(
            task_id="anl_product_performance_by_family",
            sql_relative_path="sql/analysis/product_performance_by_family.sql",
        )

        anl_product_revenue_monthly_by_family = build_bq_sql_task(
            task_id="anl_product_revenue_monthly_by_family",
            sql_relative_path="sql/analysis/product_revenue_monthly_by_family.sql",
        )

        anl_product_family_recent_trends = build_bq_sql_task(
            task_id="anl_product_family_recent_trends",
            sql_relative_path="sql/analysis/product_family_recent_trends.sql",
        )

        anl_customer_order_behavior = build_bq_sql_task(
            task_id="anl_customer_order_behavior",
            sql_relative_path="sql/analysis/customer_order_behavior.sql",
        )

        anl_customer_recency_segments = build_bq_sql_task(
            task_id="anl_customer_recency_segments",
            sql_relative_path="sql/analysis/customer_recency_segments.sql",
        )

        anl_customer_cohort_retention = build_bq_sql_task(
            task_id="anl_customer_cohort_retention",
            sql_relative_path="sql/analysis/customer_cohort_retention.sql",
        )

        anl_customer_rfm_segments = build_bq_sql_task(
            task_id="anl_customer_rfm_segments",
            sql_relative_path="sql/analysis/customer_rfm_segments.sql",
        )

        anl_product_family_customer_mix = build_bq_sql_task(
            task_id="anl_product_family_customer_mix",
            sql_relative_path="sql/analysis/product_family_customer_mix.sql",
        )

        anl_daily_kpi_summary = build_bq_sql_task(
            task_id="anl_daily_kpi_summary",
            sql_relative_path="sql/analysis/daily_kpi_summary.sql",
        )

        anl_monthly_business_summary = build_bq_sql_task(
            task_id="anl_monthly_business_summary",
            sql_relative_path="sql/analysis/monthly_business_summary.sql",
        )

        anl_customer_summary = build_bq_sql_task(
            task_id="anl_customer_summary",
            sql_relative_path="sql/analysis/customer_summary.sql",
        )

        anl_family_summary = build_bq_sql_task(
            task_id="anl_family_summary",
            sql_relative_path="sql/analysis/family_summary.sql",
        )

        anl_product_performance_by_family >> anl_product_revenue_monthly_by_family
        anl_product_revenue_monthly_by_family >> anl_product_family_recent_trends

        anl_customer_order_behavior >> anl_customer_recency_segments
        anl_customer_order_behavior >> anl_customer_cohort_retention
        anl_customer_order_behavior >> anl_customer_rfm_segments

        [
            anl_product_performance_by_family,
            anl_product_revenue_monthly_by_family,
            anl_customer_order_behavior,
            anl_customer_recency_segments,
            anl_customer_cohort_retention,
            anl_customer_rfm_segments,
        ] >> anl_product_family_customer_mix

        [
            anl_customer_order_behavior,
            anl_customer_recency_segments,
            anl_customer_cohort_retention,
            anl_customer_rfm_segments,
            anl_product_performance_by_family,
            anl_product_revenue_monthly_by_family,
            anl_product_family_recent_trends,
            anl_product_family_customer_mix,
        ] >> anl_daily_kpi_summary

        [
            anl_daily_kpi_summary,
            anl_product_performance_by_family,
            anl_product_revenue_monthly_by_family,
        ] >> anl_monthly_business_summary

        [
            anl_daily_kpi_summary,
            anl_customer_order_behavior,
            anl_customer_recency_segments,
            anl_customer_cohort_retention,
            anl_customer_rfm_segments,
        ] >> anl_customer_summary

        [
            anl_daily_kpi_summary,
            anl_product_performance_by_family,
            anl_product_revenue_monthly_by_family,
            anl_product_family_recent_trends,
            anl_product_family_customer_mix,
        ] >> anl_family_summary

    with TaskGroup(group_id="validation") as validation:
        validate_dim_customers = build_bq_sql_task(
            task_id="validate_dim_customers",
            sql_relative_path="sql/validation/assertions/dim_customers_assertions.sql",
        )

        validate_fct_orders = build_bq_sql_task(
            task_id="validate_fct_orders",
            sql_relative_path="sql/validation/assertions/fct_orders_assertions.sql",
        )

        validate_fct_order_items = build_bq_sql_task(
            task_id="validate_fct_order_items",
            sql_relative_path="sql/validation/assertions/fct_order_items_assertions.sql",
        )

        validate_product_family_models = build_bq_sql_task(
            task_id="validate_product_family_models",
            sql_relative_path="sql/validation/assertions/product_family_models_assertions.sql",
        )

        validate_anl_daily_kpi_summary = build_bq_sql_task(
            task_id="validate_anl_daily_kpi_summary",
            sql_relative_path="sql/validation/assertions/anl_daily_kpi_summary_assertions.sql",
        )

        [
            validate_dim_customers,
            validate_fct_orders,
            validate_fct_order_items,
            validate_product_family_models,
        ] >> validate_anl_daily_kpi_summary

    file_checks >> raw_load >> raw_rebuild >> staging >> marts >> analysis >> validation