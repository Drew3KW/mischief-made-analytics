# Milestone 27: Docker Local Environment Hardening

## Summary

This milestone hardened the local Docker Compose Airflow environment introduced in Milestone 25.

The goal was not to change warehouse logic or redesign the Airflow DAGs. Instead, this milestone focused on making the local Airflow runtime safer, clearer, and easier to reproduce before moving into Shopify API ingestion work.

The project now has a cleaner local Docker setup with:

- a committed `.env.example` template
- a local-only `.env` file for machine-specific configuration
- a `.dockerignore` file to keep secrets, data drops, logs, and runtime files out of Docker build context
- improved `.gitignore` protection for local-only files
- a cleaner `docker-compose.yml` that uses environment variables instead of hardcoding local configuration values
- a validated VS Code + Docker Compose + Airflow localhost UI workflow

The full raw-load + warehouse refresh + validation DAG was re-run successfully after the cleanup.

## Why this milestone mattered

Milestone 25 proved that Docker Compose was a more stable local Airflow runtime than `airflow standalone`.

However, the first working Docker Compose version still had some local configuration values hardcoded directly in `docker-compose.yml`. That was acceptable for proving the Docker MVP, but not ideal as the project continues toward:

- Shopify API ingestion
- more source systems
- stronger documentation
- portfolio-readiness
- safer local development conventions

Milestone 26 cleaned up the environment without changing the core pipeline.

## Scope

This milestone focused on local environment hardening only.

Included:

- reviewed the current Docker Compose Airflow setup
- added `.env.example`
- created a local-only `.env` file from `.env.example`
- moved configurable Docker/Airflow/GCP values into environment variables
- added `.dockerignore`
- tightened `.gitignore`
- confirmed local secret/data/runtime files are protected from Git
- restarted the Docker Compose Airflow stack
- confirmed Airflow DAG discovery still works
- triggered and validated the full raw-load + warehouse refresh + validation DAG

Not included:

- no warehouse business logic changes
- no SQL model changes
- no DAG redesign
- no Shopify API work yet
- no cloud deployment
- no CI/CD
- no secrets manager
- no Celery/Redis executor setup

## Files changed

### `.env.example`

Added a safe committed template for local configuration.

This file documents the expected local environment variables without committing real secrets.

It includes local configuration for:

- Airflow image name
- Airflow executor
- Airflow API server URL
- Airflow auth manager
- Airflow JWT secret placeholder
- local Airflow admin user
- Postgres metadata database values
- GCP / BigQuery credential path
- environment-backed `google_cloud_default` Airflow connection

The real local `.env` file is intentionally not committed.

### `.dockerignore`

Added Docker build-context protection for files that should not be copied into Docker image builds.

Ignored local-only files include:

- `.env`
- `keys/`
- `logs/`
- `.airflow/`
- `local_data/`
- local Python environments
- Python cache files
- OS/editor artifacts

This keeps Docker builds cleaner and reduces the risk of accidentally including local secrets or data files in an image build context.

### `.gitignore`

Updated local file protections.

Important local-only files and folders are ignored, including:

- `.env`
- `keys/`
- `logs/`
- `.airflow/`
- `local_data/`
- local Python virtual environments
- Python cache files

This protects:

- GCP service account keys
- local Shopify CSV exports
- local Airflow logs
- local environment configuration
- generated runtime files

### `docker-compose.yml`

Updated the Docker Compose configuration to use environment variables.

The Docker Compose stack still includes the same core services:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

The environment configuration is now cleaner and more reproducible through `.env` / `.env.example`.

The Airflow connection for BigQuery is still provided through:

- `AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT`

The GCP service account key is still mounted locally at:

```text
keys/gcp-sa.json
```

Inside the Airflow containers, this is available at:

```text
/opt/airflow/keys/gcp-sa.json
```

## Local environment workflow

The preferred local workflow is now:

1. edit files in VS Code
2. run Docker Compose commands from the VS Code terminal
3. use the Airflow localhost web UI for DAG triggering and task inspection

The Airflow UI runs at:

```text
http://localhost:8080
```

The main local DAG for end-to-end testing is:

```text
mm_shopify_raw_load_and_refresh_mvp
```

This DAG:

1. checks local Shopify CSV files
2. loads customers/products/orders CSVs into `raw_load`
3. rebuilds canonical `raw` customers/products/orders
4. refreshes staging models
5. refreshes marts models
6. refreshes analysis models
7. runs machine-readable validation assertions

## Local-only files

These files are required for local execution but should not be committed:

```text
.env
keys/gcp-sa.json
local_data/shopify/customers.csv
local_data/shopify/products.csv
local_data/shopify/orders.csv
logs/
```

The committed template is:

```text
.env.example
```

To create a local environment file:

```bash
cp .env.example .env
```

Then edit `.env` locally in VS Code.

## Validation performed

After adding the environment hardening changes:

1. Docker Compose was shut down.
2. Airflow initialization was run again.
3. Docker Compose services were restarted.
4. Airflow services came up successfully.
5. Airflow DAG discovery worked.
6. The missing `AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT` warning was resolved after creating the local `.env` file.
7. The full raw-load + warehouse refresh + validation DAG was triggered.
8. The DAG succeeded end to end.

Validated DAG:

```text
mm_shopify_raw_load_and_refresh_mvp
```

## Important issue resolved

During validation, Docker Compose initially printed warnings like:

```text
The "AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT" variable is not set. Defaulting to a blank string.
```

This happened because `.env.example` had been created, but the local `.env` file had not yet been created.

Resolution:

```bash
cp .env.example .env
```

After `.env` existed and included `AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT`, the warnings disappeared and the DAG succeeded.

## Result

The Dockerized local Airflow environment is now cleaner, safer, and easier to reproduce.

The project now has:

- a stable Docker Compose Airflow runtime
- environment-based local configuration
- protected local secrets and data files
- a documented `.env.example`
- a validated local GCP / BigQuery connection
- a working Airflow localhost UI workflow
- preserved local CSV ingestion fallback

This milestone strengthens the operational foundation without changing business logic.

## Relationship to future milestones

This milestone prepares the project for the next ingestion phase.

The current local CSV ingestion path remains the known-good baseline.

The likely next milestone is:

```text
Milestone 27: Shopify API Ingestion Spike
```

That future work should explore direct Shopify API extraction in parallel with the current CSV pipeline.

Preferred future migration path:

```text
Shopify API
  -> separate API landing/test tables
  -> comparison against CSV-derived warehouse outputs
  -> eventual canonical raw rebuild
```

The existing CSV ingestion DAG should remain available as a fallback until API-derived data is validated against the current warehouse outputs.

## Key lesson

A working local orchestration environment is not only about getting containers to start.

For an analytics engineering project, the local environment also needs to make configuration, credentials, secrets, source files, runtime logs, and reproducibility explicit.

This milestone made those boundaries clearer while keeping the project beginner-friendly and practical.
