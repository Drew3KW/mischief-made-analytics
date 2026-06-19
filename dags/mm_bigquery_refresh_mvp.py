from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

try:
    from airflow.sdk import DAG, TaskGroup
except ImportError:
    from airflow import DAG
    from airflow.utils.task_group import TaskGroup

try:
    from airflow.providers.standard.operators.python import PythonOperator
except ImportError:
    from airflow.operators.python import PythonOperator


# Repo root = parent of the dags/ folder
REPO_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_ARGS = {
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


def run_bigquery_sql(
    *,
    sql_relative_path: str,
    gcp_conn_id: str = "google_cloud_default",
    project_id: str = "mischief-made-analytics",
    location: str = "US",
) -> None:
    """Run a SQL file in BigQuery.

    Important:
    Google provider imports happen inside the task function so Airflow does not
    perform heavy BigQuery/Google imports while parsing the DAG.
    """
    from airflow.providers.google.common.hooks.base_google import GoogleBaseHook
    from google.cloud import bigquery

    sql_path = REPO_ROOT / sql_relative_path
    sql = sql_path.read_text(encoding="utf-8")

    hook = GoogleBaseHook(gcp_conn_id=gcp_conn_id)
    credentials = hook.get_credentials()

    client = bigquery.Client(
        project=project_id,
        credentials=credentials,
    )

    print(f"Running BigQuery SQL file: {sql_relative_path}")

    query_job = client.query(
        sql,
        location=location,
    )
    query_job.result()

    print(f"Completed BigQuery job: {query_job.job_id}")


def build_bq_sql_task(
    *,
    task_id: str,
    sql_relative_path: str,
    gcp_conn_id: str = "google_cloud_default",
    project_id: str = "mischief-made-analytics",
    location: str = "US",
) -> PythonOperator:
    return PythonOperator(
        task_id=task_id,
        python_callable=run_bigquery_sql,
        op_kwargs={
            "sql_relative_path": sql_relative_path,
            "gcp_conn_id": gcp_conn_id,
            "project_id": project_id,
            "location": location,
        },
    )


with DAG(
    dag_id="mm_bigquery_refresh_mvp",
    description="Manual MVP refresh for staging, marts, analysis, and validation layers in BigQuery.",
    start_date=datetime(2026, 4, 1),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["mischief-made", "bigquery", "portfolio", "mvp"],
) as dag:
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

        stg_etsy_receipts = build_bq_sql_task(
            task_id="stg_etsy_receipts",
            sql_relative_path="sql/staging/stg_etsy_receipts.sql",
        )

        stg_etsy_receipt_transactions = build_bq_sql_task(
            task_id="stg_etsy_receipt_transactions",
            sql_relative_path="sql/staging/stg_etsy_receipt_transactions.sql",
        )

        stg_etsy_receipt_payments = build_bq_sql_task(
            task_id="stg_etsy_receipt_payments",
            sql_relative_path="sql/staging/stg_etsy_receipt_payments.sql",
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

        fct_etsy_orders = build_bq_sql_task(
            task_id="fct_etsy_orders",
            sql_relative_path="sql/marts/fct_etsy_orders.sql",
        )

        fct_etsy_order_items = build_bq_sql_task(
            task_id="fct_etsy_order_items",
            sql_relative_path="sql/marts/fct_etsy_order_items.sql",
        )

        fct_etsy_payments = build_bq_sql_task(
            task_id="fct_etsy_payments",
            sql_relative_path="sql/marts/fct_etsy_payments.sql",
        )

        dim_etsy_customers = build_bq_sql_task(
            task_id="dim_etsy_customers",
            sql_relative_path="sql/marts/dim_etsy_customers.sql",
        )

        dim_etsy_listings = build_bq_sql_task(
            task_id="dim_etsy_listings",
            sql_relative_path="sql/marts/dim_etsy_listings.sql",
        )

        fct_cross_channel_orders = build_bq_sql_task(
            task_id="fct_cross_channel_orders",
            sql_relative_path="sql/marts/fct_cross_channel_orders.sql",
        )

        cross_channel_customer_bridge = build_bq_sql_task(
            task_id="cross_channel_customer_bridge",
            sql_relative_path="sql/marts/cross_channel_customer_bridge.sql",
        )

        cross_channel_product_family_bridge = build_bq_sql_task(
            task_id="cross_channel_product_family_bridge",
            sql_relative_path="sql/marts/cross_channel_product_family_bridge.sql",
        )

        dim_cross_channel_customers = build_bq_sql_task(
            task_id="dim_cross_channel_customers",
            sql_relative_path="sql/marts/dim_cross_channel_customers.sql",
        )

        dim_cross_channel_product_families = build_bq_sql_task(
            task_id="dim_cross_channel_product_families",
            sql_relative_path="sql/marts/dim_cross_channel_product_families.sql",
        )

        product_cogs_map = build_bq_sql_task(
            task_id="product_cogs_map",
            sql_relative_path="sql/marts/product_cogs_map.sql",
        )

        product_family_cogs_map = build_bq_sql_task(
            task_id="product_family_cogs_map",
            sql_relative_path="sql/marts/product_family_cogs_map.sql",
        )

        product_name_type_cogs_map = build_bq_sql_task(
            task_id="product_name_type_cogs_map",
            sql_relative_path="sql/marts/product_name_type_cogs_map.sql",
        )

        product_family_cogs_override_map = build_bq_sql_task(
            task_id="product_family_cogs_override_map",
            sql_relative_path="sql/marts/product_family_cogs_override_map.sql",
        )

        fct_cross_channel_order_items = build_bq_sql_task(
            task_id="fct_cross_channel_order_items",
            sql_relative_path="sql/marts/fct_cross_channel_order_items.sql",
        )

        # Shopify product and family dependencies.
        dim_products_historical >> dim_products
        dim_products >> product_family_map >> dim_product_families

        # Shopify order fact dependencies.
        dim_customers >> fct_orders >> fct_order_items
        dim_products >> fct_order_items
        dim_product_families >> fct_order_items

        # Etsy dimension/fact dependencies.
        fct_etsy_orders >> dim_etsy_customers
        fct_etsy_order_items >> dim_etsy_listings

        # Cross-channel order-level mart.
        [
            fct_orders,
            fct_etsy_orders,
        ] >> fct_cross_channel_orders

        # Cross-channel customer and product-family hardening.
        [
            dim_customers,
            dim_etsy_customers,
        ] >> cross_channel_customer_bridge >> dim_cross_channel_customers

        [
            dim_product_families,
            dim_etsy_listings,
        ] >> cross_channel_product_family_bridge >> dim_cross_channel_product_families

        # COGS maps.
        product_family_map >> product_cogs_map
        product_cogs_map >> product_family_cogs_map
        product_cogs_map >> product_name_type_cogs_map
        product_family_map >> product_family_cogs_override_map

        # Cross-channel item-level profitability foundation.
        # This must run after Shopify/Etsy item facts and COGS maps are fresh.
        [
            fct_order_items,
            fct_etsy_order_items,
            dim_cross_channel_customers,
            dim_cross_channel_product_families,
            product_cogs_map,
            product_family_cogs_map,
            product_name_type_cogs_map,
            product_family_cogs_override_map,
        ] >> fct_cross_channel_order_items

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

        anl_dashboard_revenue_daily = build_bq_sql_task(
            task_id="anl_dashboard_revenue_daily",
            sql_relative_path="sql/analysis/dashboard_revenue_daily.sql",
        )

        anl_dashboard_revenue_monthly = build_bq_sql_task(
            task_id="anl_dashboard_revenue_monthly",
            sql_relative_path="sql/analysis/dashboard_revenue_monthly.sql",
        )

        anl_dashboard_channel_daily = build_bq_sql_task(
            task_id="anl_dashboard_channel_daily",
            sql_relative_path="sql/analysis/dashboard_channel_daily.sql",
        )

        anl_dashboard_product_family_summary = build_bq_sql_task(
            task_id="anl_dashboard_product_family_summary",
            sql_relative_path="sql/analysis/dashboard_product_family_summary.sql",
        )

        anl_dashboard_customer_health = build_bq_sql_task(
            task_id="anl_dashboard_customer_health",
            sql_relative_path="sql/analysis/dashboard_customer_health.sql",
        )

        anl_cross_channel_customer_overlap_audit = build_bq_sql_task(
            task_id="anl_cross_channel_customer_overlap_audit",
            sql_relative_path="sql/analysis/cross_channel_customer_overlap_audit.sql",
        )

        anl_cross_channel_product_family_mapping_audit = build_bq_sql_task(
            task_id="anl_cross_channel_product_family_mapping_audit",
            sql_relative_path="sql/analysis/cross_channel_product_family_mapping_audit.sql",
        )

        anl_product_profitability_summary = build_bq_sql_task(
            task_id="anl_product_profitability_summary",
            sql_relative_path="sql/analysis/product_profitability_summary.sql",
        )

        anl_product_profitability_monthly = build_bq_sql_task(
            task_id="anl_product_profitability_monthly",
            sql_relative_path="sql/analysis/product_profitability_monthly.sql",
        )

        # Existing product analytics dependencies.
        anl_product_performance_by_family >> anl_product_revenue_monthly_by_family
        anl_product_revenue_monthly_by_family >> anl_product_family_recent_trends

        # Existing customer analytics dependencies.
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

        # Dashboard analysis dependencies.
        anl_dashboard_revenue_daily >> anl_dashboard_revenue_monthly
        anl_family_summary >> anl_dashboard_product_family_summary
        anl_customer_summary >> anl_dashboard_customer_health

        # Profitability views.
        # Monthly does not technically depend on summary, but chaining keeps
        # the profitability section easy to read in the Airflow graph.
        anl_product_profitability_summary >> anl_product_profitability_monthly

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

        validate_etsy_staging = build_bq_sql_task(
            task_id="validate_etsy_staging",
            sql_relative_path="sql/validation/etsy_staging_validation.sql",
        )

        validate_etsy_marts = build_bq_sql_task(
            task_id="validate_etsy_marts",
            sql_relative_path="sql/validation/etsy_marts_validation.sql",
        )

        validate_etsy_dimensions = build_bq_sql_task(
            task_id="validate_etsy_dimensions",
            sql_relative_path="sql/validation/etsy_dimensions_validation.sql",
        )

        validate_dashboard_mvp = build_bq_sql_task(
            task_id="validate_dashboard_mvp",
            sql_relative_path="sql/validation/dashboard_mvp_validation.sql",
        )

        validate_cross_channel_identity_hardening = build_bq_sql_task(
            task_id="validate_cross_channel_identity_hardening",
            sql_relative_path="sql/validation/cross_channel_identity_hardening_validation.sql",
        )

        validate_profitability_foundation = build_bq_sql_task(
            task_id="validate_profitability_foundation",
            sql_relative_path="sql/validation/profitability_foundation_validation.sql",
        )

        [
            validate_dim_customers,
            validate_fct_orders,
            validate_fct_order_items,
            validate_product_family_models,
        ] >> validate_anl_daily_kpi_summary

        validate_etsy_staging >> validate_etsy_marts >> validate_etsy_dimensions

        [
            anl_dashboard_revenue_monthly,
            anl_dashboard_channel_daily,
            anl_dashboard_product_family_summary,
            anl_dashboard_customer_health,
        ] >> validate_dashboard_mvp

        [
            validate_anl_daily_kpi_summary,
            validate_etsy_dimensions,
            validate_dashboard_mvp,
            validate_cross_channel_identity_hardening,
        ] >> validate_profitability_foundation

    staging >> marts >> analysis >> validation