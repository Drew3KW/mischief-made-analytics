# 24 - Airflow Scheduled Refresh MVP

## Summary

Extended the local Airflow MVP from manual-only orchestration into scheduled warehouse refresh.

This milestone updates the existing `mm_bigquery_refresh_mvp` DAG so the pipeline can now run on a recurring schedule rather than only through manual execution in the Airflow UI.

The goal of this phase was to add the smallest realistic scheduling upgrade before taking on the larger complexity of raw CSV load orchestration.

## What changed

### Airflow DAG scheduling update

Updated:

- `dags/mm_bigquery_refresh_mvp.py`

Key changes:

- added a daily Airflow schedule
- retained `catchup=False`
- retained `max_active_runs=1`
- added a lightweight retry policy:
  - `retries=1`
  - `retry_delay=timedelta(minutes=5)`

### Current DAG behavior

The DAG now supports both:

- manual trigger
- scheduled trigger

Current DAG flow remains:

- `staging`
- `marts`
- `analysis`
- `validation`

This preserves the existing warehouse refresh and validation sequence while adding recurring execution behavior.

## Scheduling design decisions

### Keep the first schedule simple

The project is still driven by manually refreshed Shopify CSV source data rather than source-system extraction inside Airflow.

Because of that, the DAG does not yet need a high-frequency schedule or more complex time-based orchestration.

This milestone intentionally uses a simple daily schedule as the smallest realistic upgrade.

### Retain `catchup=False`

This DAG is meant to refresh the current warehouse state, not automatically replay every historical interval since `start_date`.

Keeping `catchup=False` avoids accidental backfill behavior during local development and makes the scheduling behavior easier to reason about.

### Retain `max_active_runs=1`

Warehouse rebuilds should not overlap.

Keeping `max_active_runs=1` protects the project from multiple concurrent runs of the same DAG and keeps the local Airflow MVP operationally simple.

### Add a minimal retry policy

A small retry policy was added to make the DAG slightly more resilient to transient failures without overengineering the local MVP.

The selected settings were intentionally conservative:

- `retries=1`
- `retry_delay=5 minutes`

## Operational concepts clarified in this milestone

### Manual trigger vs scheduled trigger

Before this milestone, the DAG only ran when manually triggered.

After this milestone, the DAG can still be triggered manually, but the scheduler can also create runs automatically based on the configured schedule.

### Schedule and cron

Airflow schedules can be expressed with presets such as `@daily` or with explicit cron expressions.

This MVP uses a simple daily schedule rather than introducing a custom cron pattern.

### Idempotent refresh behavior

The warehouse refresh tasks are designed around rerunnable SQL patterns, so repeated DAG execution is intended to rebuild the same warehouse objects cleanly rather than append duplicate outputs.

That makes scheduled execution much safer than it would be in a non-idempotent pipeline design.

### Local scheduler dependency

Because this is still a local WSL / Ubuntu Airflow setup, scheduled runs only occur while the Airflow scheduler is actually running and the machine remains awake.

This is an acceptable constraint for the current MVP and an important operational limitation to document clearly.

## Issues encountered and resolved

### DAG import error after retry configuration update

The first scheduling revision introduced a DAG import failure because `timedelta` was referenced before being imported.

This was resolved by updating the import statement to include:

- `from datetime import datetime, timedelta`

### Scheduled-run verification required timezone awareness

Because the DAG uses a daily schedule and the local Airflow configuration uses UTC, the first scheduled run did not occur immediately after the code change.

Verification required confirming:

- the DAG was unpaused
- the scheduler was running
- the Airflow default timezone was UTC
- the machine would remain awake long enough for the first scheduled interval to be created

## Result

The scheduled-refresh update was validated in two ways:

1. manual regression test:
   - DAG parsed successfully
   - manual trigger completed successfully
   - all task groups succeeded

2. scheduled execution test:
   - Airflow scheduler created the automatic daily run
   - all tasks succeeded under scheduled execution as well

The local Airflow MVP now supports both recurring refresh and downstream validation for the BigQuery warehouse.

## Why this matters

This milestone moves the project from:

- orchestrated warehouse refresh with validation
to:
- orchestrated warehouse refresh with validation and recurring scheduled execution

That improves the project in two ways:

1. operational realism:
   - the warehouse now behaves more like a real maintained analytics pipeline rather than a manually kicked-off workflow

2. portfolio quality:
   - the repo now demonstrates orchestration, validation, and basic scheduling together in a coherent analytics engineering workflow

## Next likely steps

With local orchestration, validation, and scheduling now all working, the next major phase can reasonably move toward:

- raw CSV load orchestration
- broader ingestion automation design
- later multi-source pipeline expansion
