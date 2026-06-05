from __future__ import annotations

import os
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.decorators import task
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator

DAG_ID = "mm_etsy_recent_refresh_mvp"

PROJECT_ID = "mischief-made-analytics"
LOCATION = "US"
GCP_CONN_ID = "google_cloud_default"

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = "/opt/airflow/scripts/etsy_orders_landing.py"

RECENT_WINDOW_DAYS = 14
RECENT_TABLE_SUFFIX = "recent_catchup_candidate"

DEFAULT_ARGS = {
    "owner": "airflow",
    "retries": 0,
}


def read_sql(sql_relative_path: str) -> str:
    sql_path = REPO_ROOT / sql_relative_path
    return sql_path.read_text()


def read_validation_sql_for_gate(sql_relative_path: str) -> str:
    sql = read_sql(sql_relative_path).strip().rstrip(";")

    # Validation files usually end with an ORDER BY for human readability.
    # The gate wraps the validation query in a subquery, so remove the final
    # ORDER BY clause before wrapping.
    upper_sql = sql.upper()
    order_by_index = upper_sql.rfind("\nORDER BY")

    if order_by_index != -1:
        return sql[:order_by_index].rstrip()

    return sql


def build_bq_sql_task(
    *,
    task_id: str,
    sql_relative_path: str,
) -> BigQueryInsertJobOperator:
    return BigQueryInsertJobOperator(
        task_id=task_id,
        gcp_conn_id=GCP_CONN_ID,
        project_id=PROJECT_ID,
        location=LOCATION,
        configuration={
            "query": {
                "query": read_sql(sql_relative_path),
                "useLegacySql": False,
            }
        },
    )


def build_bq_validation_gate_task(
    *,
    task_id: str,
    validation_sql_relative_path: str,
) -> BigQueryInsertJobOperator:
    validation_sql = read_validation_sql_for_gate(validation_sql_relative_path)

    gate_sql = f"""
    WITH validation_results AS (
        {validation_sql}
    ),

    failures AS (
        SELECT
            COUNTIF(check_status = 'FAIL') AS fail_count
        FROM validation_results
    )

    SELECT
        IF(
            fail_count = 0,
            'PASS',
            ERROR(
                CONCAT(
                    '{task_id} failed with ',
                    CAST(fail_count AS STRING),
                    ' FAIL rows.'
                )
            )
        ) AS validation_gate_status
    FROM failures
    """

    return BigQueryInsertJobOperator(
        task_id=task_id,
        gcp_conn_id=GCP_CONN_ID,
        project_id=PROJECT_ID,
        location=LOCATION,
        configuration={
            "query": {
                "query": gate_sql,
                "useLegacySql": False,
            }
        },
    )


def recent_window_dates() -> tuple[str, str]:
    end_date = datetime.now(UTC).date()
    start_date = end_date - timedelta(days=RECENT_WINDOW_DAYS)

    return start_date.isoformat(), end_date.isoformat()


with DAG(
    dag_id=DAG_ID,
    default_args=DEFAULT_ARGS,
    description=(
        "Refresh recent Etsy landing tables, promote latest Etsy raw_load "
        "tables, and rebuild Etsy and cross-channel revenue models."
    ),
    start_date=datetime(2026, 5, 26, 0, 0, tzinfo=UTC),
    schedule="30 21 * * *",
    catchup=False,
    max_active_runs=1,
    tags=["mischief-made", "etsy", "cross-channel", "api", "mvp"],
) as dag:

    @task
    def run_etsy_recent_landing() -> None:
        start_date, end_date = recent_window_dates()

        command = [
            "python",
            SCRIPT_PATH,
            "--start-date",
            start_date,
            "--end-date",
            end_date,
            "--chunk-days",
            str(RECENT_WINDOW_DAYS + 1),
            "--table-suffix",
            RECENT_TABLE_SUFFIX,
            "--write-mode",
            "replace",
        ]

        print("Running Etsy recent landing command:")
        print(" ".join(command))

        env = os.environ.copy()
        env["GOOGLE_APPLICATION_CREDENTIALS"] = "/opt/airflow/keys/gcp-sa.json"

        result = subprocess.run(
            command,
            env=env,
            text=True,
            capture_output=True,
        )

        print("STDOUT:")
        print(result.stdout)

        print("STDERR:")
        print(result.stderr)

        if result.returncode != 0:
            raise RuntimeError(
                "Etsy recent landing failed with return code "
                f"{result.returncode}."
            )

    promote_recent_catchup = build_bq_sql_task(
        task_id="promote_etsy_recent_catchup_candidates_to_latest",
        sql_relative_path="sql/raw/promote_etsy_recent_catchup_candidates_to_latest.sql",
    )

    validate_etsy_landing = build_bq_validation_gate_task(
        task_id="validate_etsy_landing_no_failures",
        validation_sql_relative_path="sql/validation/etsy_orders_landing_validation.sql",
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

    validate_etsy_staging = build_bq_validation_gate_task(
        task_id="validate_etsy_staging_no_failures",
        validation_sql_relative_path="sql/validation/etsy_staging_validation.sql",
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

    validate_etsy_marts = build_bq_validation_gate_task(
        task_id="validate_etsy_marts_no_failures",
        validation_sql_relative_path="sql/validation/etsy_marts_validation.sql",
    )

    dim_etsy_customers = build_bq_sql_task(
        task_id="dim_etsy_customers",
        sql_relative_path="sql/marts/dim_etsy_customers.sql",
    )

    dim_etsy_listings = build_bq_sql_task(
        task_id="dim_etsy_listings",
        sql_relative_path="sql/marts/dim_etsy_listings.sql",
    )

    validate_etsy_dimensions = build_bq_validation_gate_task(
        task_id="validate_etsy_dimensions_no_failures",
        validation_sql_relative_path="sql/validation/etsy_dimensions_validation.sql",
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

    validate_cross_channel_identity_hardening = build_bq_validation_gate_task(
        task_id="validate_cross_channel_identity_hardening_no_failures",
        validation_sql_relative_path="sql/validation/cross_channel_identity_hardening_validation.sql",
    )

    fct_cross_channel_orders = build_bq_sql_task(
        task_id="fct_cross_channel_orders",
        sql_relative_path="sql/marts/fct_cross_channel_orders.sql",
    )

    cross_channel_revenue_daily = build_bq_sql_task(
        task_id="cross_channel_revenue_daily",
        sql_relative_path="sql/analysis/cross_channel_revenue_daily.sql",
    )

    cross_channel_revenue_daily_pivot = build_bq_sql_task(
        task_id="cross_channel_revenue_daily_pivot",
        sql_relative_path="sql/analysis/cross_channel_revenue_daily_pivot.sql",
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

    validate_cross_channel_revenue = build_bq_validation_gate_task(
        task_id="validate_cross_channel_revenue_no_failures",
        validation_sql_relative_path="sql/validation/cross_channel_revenue_validation.sql",
    )

    validate_dashboard_mvp = build_bq_validation_gate_task(
        task_id="validate_dashboard_mvp_no_failures",
        validation_sql_relative_path="sql/validation/dashboard_mvp_validation.sql",
    )

    etsy_recent_landing = run_etsy_recent_landing()

    etsy_recent_landing >> promote_recent_catchup >> validate_etsy_landing

    validate_etsy_landing >> [
        stg_etsy_receipts,
        stg_etsy_receipt_transactions,
        stg_etsy_receipt_payments,
    ]

    [
        stg_etsy_receipts,
        stg_etsy_receipt_transactions,
        stg_etsy_receipt_payments,
    ] >> validate_etsy_staging

    validate_etsy_staging >> [
        fct_etsy_orders,
        fct_etsy_order_items,
        fct_etsy_payments,
    ]

    [
        fct_etsy_orders,
        fct_etsy_order_items,
        fct_etsy_payments,
    ] >> validate_etsy_marts

    fct_etsy_orders >> dim_etsy_customers
    fct_etsy_order_items >> dim_etsy_listings

    [
        dim_etsy_customers,
        dim_etsy_listings,
    ] >> validate_etsy_dimensions

    validate_etsy_dimensions >> [
        cross_channel_customer_bridge,
        cross_channel_product_family_bridge,
    ]

    cross_channel_customer_bridge >> dim_cross_channel_customers
    cross_channel_product_family_bridge >> dim_cross_channel_product_families

    [
        dim_cross_channel_customers,
        dim_cross_channel_product_families,
    ] >> validate_cross_channel_identity_hardening

    validate_cross_channel_identity_hardening >> fct_cross_channel_orders

    fct_cross_channel_orders >> [
        cross_channel_revenue_daily,
        cross_channel_revenue_daily_pivot,
        anl_dashboard_revenue_daily,
        anl_dashboard_channel_daily,
    ]

    anl_dashboard_revenue_daily >> anl_dashboard_revenue_monthly

    [
        cross_channel_revenue_daily,
        cross_channel_revenue_daily_pivot,
    ] >> validate_cross_channel_revenue

    [
        anl_dashboard_revenue_monthly,
        anl_dashboard_channel_daily,
        validate_cross_channel_revenue,
    ] >> validate_dashboard_mvp