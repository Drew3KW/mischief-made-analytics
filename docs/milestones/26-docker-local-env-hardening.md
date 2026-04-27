# Milestone 26: Docker Local Environment Hardening

## Summary

This milestone hardened the local Docker Compose Airflow environment introduced in Milestone 25.

The goal was not to change warehouse logic or redesign the Airflow DAGs. Instead, this milestone focused on making the local Airflow runtime safer, clearer, and easier to reproduce before moving into Shopify API ingestion work.

The project now has a cleaner local Docker setup with:

- a committed `.env.example` template
- a local-only `.env` file for machine-specific configuration
- a `.dockerignore` file to keep secrets, data drops, logs, and local runtime files out of Docker build context
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
