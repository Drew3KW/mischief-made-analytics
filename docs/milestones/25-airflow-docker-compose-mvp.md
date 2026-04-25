# Milestone 25: Airflow Docker Compose MVP

## Overview

This milestone replaces the local Airflow `standalone` environment with a Docker Compose–based setup to provide a more stable, reproducible orchestration layer for the Mischief Made analytics pipeline.

The goal was to preserve all existing DAG logic and warehouse behavior while improving reliability and developer ergonomics.

---

## Motivation

The previous local Airflow setup (`airflow standalone`) proved unstable during iterative development, with issues including:

- UI instability (blank screens, API inconsistencies)
- stale DAG metadata
- unreliable localhost behavior
- mismatch between CLI and UI state

These issues made debugging difficult and reduced confidence in DAG execution.

---

## Approach

A Docker Compose–based Airflow 3 environment was implemented with the following components:

- `postgres` → Airflow metadata database
- `airflow-apiserver` → Airflow 3 API/UI
- `airflow-scheduler` → DAG scheduling + execution
- `airflow-dag-processor` → DAG parsing
- `airflow-init` → database initialization + user creation

Key design principles:

- Keep the setup MVP-sized and portfolio-appropriate
- Preserve existing DAGs and repo structure
- Mount repo directories directly into containers
- Avoid overengineering (no Celery, no distributed setup)

---

## Key Implementation Details

### Dockerization

Added:

- `docker-compose.yml`
- `Dockerfile.airflow`
- `airflow/requirements.txt`

Custom image includes:

- `apache-airflow-providers-google`
- `apache-airflow-providers-standard`
- `apache-airflow-providers-fab`
- `google-cloud-bigquery`

---

### Volume Mounting

The following directories are mounted into the container:

| Local Path | Container Path |
|----------|----------------|
| `dags/` | `/opt/airflow/dags` |
| `sql/` | `/opt/airflow/sql` |
| `local_data/` | `/opt/airflow/local_data` |
| `logs/` | `/opt/airflow/logs` |
| `keys/` | `/opt/airflow/keys` |

This allows existing DAG code using repo-relative paths to continue working unchanged.

---

### Authentication

#### GCP Authentication

- Service account JSON stored locally in `keys/gcp-sa.json`
- Mounted into container
- Used via:
  - `GOOGLE_APPLICATION_CREDENTIALS`
  - Airflow connection `google_cloud_default`

#### Airflow Connection

Configured via environment variable:

```bash
AIRFLOW_CONN_GOOGLE_CLOUD_DEFAULT
