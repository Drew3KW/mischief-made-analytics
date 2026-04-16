# 22 - Airflow Local MVP Orchestration

## Summary

This milestone introduces the first Apache Airflow orchestration layer for the Mischief Made analytics project.

It adds a local Airflow MVP that can orchestrate the existing BigQuery warehouse refresh flow across:

- staging
- marts
- analysis / summary models

This is the project’s first orchestration milestone and marks the transition from manually run SQL modeling work toward a real pipeline execution framework.

## What changed

### New orchestration DAG

Added:

- `dags/mm_bigquery_refresh_mvp.py`

This DAG runs the current warehouse in dependency order:

- `staging`
- `marts`
- `analysis`

### Local Airflow project setup

Added or updated local project setup so Airflow can be run in a local WSL / Ubuntu environment against the repo’s checked-in SQL files.

This milestone also established the local development pattern for:

- repo-level `dags/`
- Airflow runtime kept out of Git
- BigQuery execution through Airflow’s Google provider
- manual trigger-first orchestration for safe local testing

### Git hygiene for local runtime artifacts

Updated `.gitignore` so local runtime / environment artifacts are not committed, including items such as:

- `.airflow/`
- `.venv/`
- `__pycache__/`

## Why this was needed

Analysis Pack v1 is now effectively complete, including the warehouse foundation, shared semantic models, family/customer analysis, and dashboard-ready summary layer.

At that point, the next logical project phase was no longer “more SQL models first,” but orchestration.

Without orchestration, the project still depended on manually running SQL in the correct order. That was acceptable during early modeling, but it limited the project in several ways:

- no formal dependency graph
- no standardized execution path
- no centralized run monitoring
- no natural place to add validations or future ingestion steps
- no orchestration layer to showcase in the portfolio

Airflow solves that by providing a real DAG-based workflow layer above the warehouse.

## Design decision

The first orchestration milestone intentionally keeps scope narrow:

- local setup first
- manual trigger first
- no automatic ingestion yet
- no validation task group yet
- no overengineering

The goal of this milestone was to prove the orchestration foundation, not to solve every future pipeline concern at once.

### MVP orchestration contract

The MVP DAG assumes raw BigQuery tables are already available.

Its responsibility is:

1. rebuild staging models
2. rebuild marts models
3. rebuild analysis / summary models

This keeps the first orchestration layer aligned with the project’s current source reality, where upstream Shopify extraction is still CSV-based.

## DAG structure

### `mm_bigquery_refresh_mvp`

The DAG executes repo-checked-in SQL files through Airflow’s BigQuery operator.

#### Task groups

- `staging`
- `marts`
- `analysis`

#### Current execution pattern

- manual trigger
- `catchup = False`
- one active run at a time
- BigQuery SQL executed directly from repo files

## Validation / test approach

Before running the full DAG, local smoke tests were used to confirm:

- Airflow installation worked in WSL / Ubuntu
- Airflow could discover repo DAG files
- Airflow could authenticate to Google Cloud
- Airflow could submit BigQuery jobs
- Airflow could execute a real checked-in SQL file
- the full MVP DAG could run successfully end to end

## Business / portfolio value

This milestone improves the project in two ways:

1. It makes the warehouse more operational by introducing a real orchestration layer.
2. It strengthens the portfolio by demonstrating Airflow-based pipeline orchestration on top of an already-developed BigQuery warehouse.

This moves the project closer to a complete analytics engineering stack rather than a collection of manually run SQL assets.

## Next likely direction

With the first Airflow DAG now working, the next orchestration steps can reasonably include:

- adding a validation task group
- defining an initial refresh schedule
- adding raw CSV load orchestration ahead of staging
- later moving toward more automated source ingestion
- expanding orchestration as new sources such as Etsy, Faire, and ads data are added
