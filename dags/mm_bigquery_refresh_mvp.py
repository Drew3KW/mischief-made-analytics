from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.sdk import TaskGroup


# Repo root = parent of the dags/ folder
REPO_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_ARGS = {
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


def build_bq_sql_task(
    *,
    task_id: str,
    sql_relative_path: str,
    gcp_conn_id: str = "google_cloud_default",
    project_id: str = "mischief-made-analytics",
    location: str = "US",
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


with DAG(
    dag_id="mm_bigquery_refresh_mvp",
    description="Manual MVP refresh for staging, marts, and analysis layers in BigQuery.",
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

        fct_cross_channel_orders = build_bq_sql_task(
            task_id="fct_cross_channel_orders",
            sql_relative_path="sql/marts/fct_cross_channel_orders.sql",
        )

        dim_products_historical >> dim_products
        dim_products >> product_family_map >> dim_product_families
        dim_customers >> fct_orders >> fct_order_items
        dim_product_families >> fct_order_items
        dim_products >> fct_order_items
        fct_orders >> fct_cross_channel_orders

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

        anl_dashboard_revenue_daily >> anl_dashboard_revenue_monthly
        anl_family_summary >> anl_dashboard_product_family_summary
        anl_customer_summary >> anl_dashboard_customer_health

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

        validate_dashboard_mvp = build_bq_sql_task(
            task_id="validate_dashboard_mvp",
            sql_relative_path="sql/validation/dashboard_mvp_validation.sql",
        )

        [
            validate_dim_customers,
            validate_fct_orders,
            validate_fct_order_items,
            validate_product_family_models,
        ] >> validate_anl_daily_kpi_summary

        [
            anl_dashboard_revenue_monthly,
            anl_dashboard_channel_daily,
            anl_dashboard_product_family_summary,
            anl_dashboard_customer_health,
        ] >> validate_dashboard_mvp

    staging >> marts >> analysis >> validation