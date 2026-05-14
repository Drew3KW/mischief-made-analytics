from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.standard.operators.trigger_dagrun import TriggerDagRunOperator
from airflow.sdk import TaskGroup

REPO_ROOT = Path(__file__).resolve().parents[1]

PROJECT_ID = "mischief-made-analytics"
LOCATION = "US"
GCP_CONN_ID = "google_cloud_default"

DEFAULT_ARGS = {
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
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
    ERROR(CONCAT('{task_id} failed with ', CAST(fail_count AS STRING), ' FAIL rows.'))
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


def build_trigger_dag_task(
    *,
    task_id: str,
    trigger_dag_id: str,
) -> TriggerDagRunOperator:
    return TriggerDagRunOperator(
        task_id=task_id,
        trigger_dag_id=trigger_dag_id,
        trigger_run_id=f"canonical_refresh__{trigger_dag_id}__{{{{ ts_nodash }}}}",
        reset_dag_run=True,
        wait_for_completion=True,
        poke_interval=60,
        allowed_states=["success"],
        failed_states=["failed"],
    )


with DAG(
    dag_id="mm_shopify_api_canonical_refresh_mvp",
    description=(
        "Orchestrates Shopify API landing, canonical raw replacement, "
        "warehouse refresh, and validation."
    ),
    default_args=DEFAULT_ARGS,
    start_date=datetime(2026, 5, 13),
    schedule="0 20 * * *",
    catchup=False,
    max_active_runs=1,
    tags=["mischief-made", "shopify", "api", "canonical-raw", "automation", "mvp"],
) as dag:
    with TaskGroup(group_id="api_landing") as api_landing:
        orders_landing = build_trigger_dag_task(
            task_id="trigger_orders_landing",
            trigger_dag_id="mm_shopify_api_orders_landing_mvp",
        )

        customers_landing = build_trigger_dag_task(
            task_id="trigger_customers_landing",
            trigger_dag_id="mm_shopify_api_customers_landing_mvp",
        )

        products_landing = build_trigger_dag_task(
            task_id="trigger_products_landing",
            trigger_dag_id="mm_shopify_api_products_landing_mvp",
        )

        orders_landing >> customers_landing >> products_landing

    with TaskGroup(group_id="api_raw_candidates") as api_raw_candidates:
        products_api_raw_candidate = build_bq_sql_task(
            task_id="products_api_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_products_api_raw_candidate.sql",
        )

        customers_api_raw_candidate = build_bq_sql_task(
            task_id="customers_api_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_customers_api_raw_candidate.sql",
        )

        orders_api_raw_candidate = build_bq_sql_task(
            task_id="orders_api_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_orders_api_raw_candidate.sql",
        )
    
    validate_api_landing_freshness = build_bq_validation_gate_task(
        task_id="validate_api_landing_freshness_no_failures",
        validation_sql_relative_path="sql/validation/shopify_api_landing_freshness_validation.sql",
    )

    validate_api_raw_candidates = build_bq_validation_gate_task(
        task_id="validate_api_raw_candidates_no_failures",
        validation_sql_relative_path="sql/validation/shopify_api_raw_candidates_validation.sql",
    )

    with TaskGroup(group_id="hybrid_raw_candidates") as hybrid_raw_candidates:
        products_hybrid_raw_candidate = build_bq_sql_task(
            task_id="products_hybrid_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_products_hybrid_raw_candidate.sql",
        )

        customers_hybrid_raw_candidate = build_bq_sql_task(
            task_id="customers_hybrid_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_customers_hybrid_raw_candidate.sql",
        )

        orders_hybrid_raw_candidate = build_bq_sql_task(
            task_id="orders_hybrid_raw_candidate",
            sql_relative_path="sql/raw/create_shopify_orders_hybrid_raw_candidate.sql",
        )

    validate_hybrid_raw_candidates = build_bq_validation_gate_task(
        task_id="validate_hybrid_raw_candidates_no_failures",
        validation_sql_relative_path="sql/validation/shopify_hybrid_raw_candidate_validation.sql",
    )

    backup_canonical_raw = build_bq_sql_task(
        task_id="backup_canonical_raw",
        sql_relative_path="sql/raw/backup_shopify_canonical_raw_pre_automated_refresh.sql",
    )

    replace_canonical_raw = build_bq_sql_task(
        task_id="replace_canonical_raw",
        sql_relative_path="sql/raw/replace_shopify_canonical_raw_from_hybrid_candidates.sql",
    )

    refresh_warehouse = build_trigger_dag_task(
        task_id="trigger_bigquery_refresh",
        trigger_dag_id="mm_bigquery_refresh_mvp",
    )

    validate_canonical_raw_replacement = build_bq_validation_gate_task(
        task_id="validate_canonical_raw_replacement_no_failures",
        validation_sql_relative_path="sql/validation/shopify_canonical_raw_replacement_validation.sql",
    )

    (
            (
        api_landing
        >> validate_api_landing_freshness
        >> api_raw_candidates
        >> validate_api_raw_candidates
        >> hybrid_raw_candidates
        >> validate_hybrid_raw_candidates
        >> backup_canonical_raw
        >> replace_canonical_raw
        >> refresh_warehouse
        >> validate_canonical_raw_replacement
    )

        
    )