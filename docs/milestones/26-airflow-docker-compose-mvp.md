# 26 - Airflow Docker Compose MVP

## Summary

This milestone migrates the local Airflow runtime from `airflow standalone` to Docker Compose.

The goal was to make the local orchestration environment more stable, reproducible, and portfolio-ready while preserving the existing DAG behavior and warehouse logic.

The full raw-load + warehouse refresh DAG now runs successfully end to end inside Docker.

Current Dockerized Airflow coverage includes:

- local Shopify CSV file-drop ingestion
- raw-load landing tables
- canonical raw rebuild
- staging refresh
- marts refresh
- analysis / summary refresh
- machine-readable validation assertions

## What changed

### Added Docker Compose Airflow runtime

Added a Docker Compose-based Airflow 3 setup with the following services:

- `postgres`
- `airflow-apiserver`
- `airflow-scheduler`
- `airflow-dag-processor`
- `airflow-init`

This replaces the previous local `airflow standalone` development pattern with a more explicit multi-service local Airflow environment.

### Added custom Airflow image

Added:

- `Dockerfile.airflow`
- `airflow/requirements.txt`

The custom Airflow image installs the packages required by the current DAGs:

- `apache-airflow-providers-standard`
- `apache-airflow-providers-google`
- `apache-airflow-providers-fab`
- `google-cloud-bigquery`
- `pandas`

This keeps the local Airflow runtime reproducible instead of relying on packages installed into a local virtual environment.

### Added Docker Compose configuration

Added:

- `docker-compose.yml`

The Compose file defines the Airflow services, shared environment configuration, mounted repo paths, and local BigQuery authentication settings.

### Added local Docker mounts

The Docker environment mounts existing repo folders into the Airflow containers:

| Repo path | Container path |
| --- | --- |
| `dags/` | `/opt/airflow/dags` |
| `sql/` | `/opt/airflow/sql` |
| `local_data/` | `/opt/airflow/local_data` |
| `logs/` | `/opt/airflow/logs` |
| `keys/` | `/opt/airflow/keys` |

This preserves the existing DAG pattern of reading checked-in SQL files from repo-relative paths.

### Added Docker-compatible GCP authentication

The Dockerized Airflow environment supports BigQuery authentication through:

- a local service account key at `keys/gcp-sa.json`
- `GOOGLE_APPLICATION_CREDENTIALS`
- an environment-backed Airflow connection for `google_cloud_default`

This supports both authentication paths used by the current DAGs:

1. direct Python BigQuery client usage in the raw CSV load tasks
2. Airflow Google provider usage in BigQuery SQL execution tasks

### Updated local file hygiene

Local runtime artifacts and sensitive files are ignored, including:

- Airflow logs
- local service account keys
- local Shopify CSV exports

The service account key and local source CSVs remain local-only and should not be committed.

## Why this was needed

The previous `airflow standalone` setup worked well enough for the first orchestration milestones, but it became unstable during repeated iterative development.

Issues encountered during the standalone phase included:

- stale example DAG metadata
- UI instability / blank screens
- localhost / API-server unreliability
- inconsistent UI and CLI behavior
- local Airflow state issues that made CLI execution more dependable than the web UI

That was acceptable during early experimentation, but it was not ideal for continued ingestion work or portfolio presentation.

Docker Compose improves the setup by making the Airflow runtime more explicit:

- services are named and visible
- metadata is stored in Postgres
- dependencies are installed into a reproducible image
- local folders are mounted deliberately
- startup and shutdown commands are standardized

## Design decisions

### Keep the scope MVP-sized

This milestone intentionally does not introduce:

- Celery
- Redis
- Kubernetes
- remote executors
- cloud deployment
- secrets managers
- dbt
- CI/CD

The goal was to stabilize the local orchestration runtime without overengineering the project.

### Use Airflow 3

The current DAGs use Airflow 3-style imports, including:

- `airflow.sdk`
- `airflow.providers.standard`

Because of that, the Docker image was aligned to Airflow 3 rather than backporting the DAGs to Airflow 2 import patterns.

### Use Postgres metadata

The Docker Compose setup uses Postgres as the Airflow metadata database.

This is more realistic and more stable than the local state created by `airflow standalone`.

### Use environment-backed Airflow connection configuration

The `google_cloud_default` Airflow connection is configured through the Docker environment rather than relying on manually created UI or metadata database state.

This proved more reliable because all Airflow services see the same connection configuration at runtime.

### Preserve the current DAG behavior

No warehouse logic was redesigned for this milestone.

The existing DAG contracts remain:

- `mm_bigquery_refresh_mvp` refreshes the warehouse from existing raw tables
- `mm_shopify_raw_load_and_refresh_mvp` loads local Shopify CSVs, rebuilds canonical raw tables, and refreshes the downstream warehouse

This keeps the Docker migration focused on orchestration runtime stability.

## Issues encountered and resolved

### Airflow image version mismatch

The initial Docker image used an Airflow 2 base image, but the repo DAGs use Airflow 3 imports.

This caused DAG import errors for:

- `airflow.sdk`
- `airflow.providers.standard`

The issue was resolved by moving the Docker image to Airflow 3 and adding the standard provider package.

### Airflow 3 auth manager setup

Airflow 3 did not expose the expected local username / password behavior until the FAB provider and auth manager were configured.

This was resolved by:

- adding `apache-airflow-providers-fab`
- configuring the FAB auth manager for local login

### Metadata DB reset

After switching from the Airflow 2 image to the Airflow 3 image during setup, the local Postgres metadata volume needed to be reset.

Because this was local development metadata, the cleanest fix was to remove the old Docker volume and reinitialize with the Airflow 3 environment.

### Execution API URL

Airflow 3 task execution requires internal communication between task execution processes and the Airflow API server.

Initial task runs failed because the scheduler / task process could not reach the API server correctly.

This was resolved by setting the internal execution API server URL in the Docker environment.

### JWT signing secret

After the execution API URL was configured, task runs still failed with internal auth-token signature errors.

This was resolved by setting a shared JWT secret across Airflow services.

### GCP connection visibility

The raw CSV load tasks authenticated successfully through `GOOGLE_APPLICATION_CREDENTIALS`, but BigQuery operator tasks failed until the Airflow connection `google_cloud_default` was also defined.

This was resolved by adding an environment-backed Airflow connection.

## Result

The Dockerized Airflow environment now works successfully.

Validated results:

- Airflow UI loads successfully at `localhost:8080`
- local admin login works
- both DAGs appear in the UI
- DAG import errors are resolved
- the Docker container can see the mounted GCP service account key
- direct BigQuery client authentication works inside Docker
- the Airflow Google provider can use `google_cloud_default`
- local Shopify CSV files are visible inside Docker
- `check_input_files` succeeds
- `raw_load` task group succeeds
- raw rebuild tasks succeed
- downstream staging tasks succeed
- downstream marts tasks succeed
- downstream analysis tasks succeed
- downstream validation tasks succeed

The full `mm_shopify_raw_load_and_refresh_mvp` DAG completed successfully end to end inside Docker.

## Current local Docker workflow

The normal local workflow is:

1. start Docker Airflow from the repo root
2. open the Airflow UI at `localhost:8080`
3. place Shopify CSV exports in `local_data/shopify/`
4. trigger the desired DAG from the Airflow UI
5. monitor the run in Grid or Graph view
6. inspect task logs in the UI if needed
7. shut down Docker when finished

Current DAGs:

- `mm_bigquery_refresh_mvp`
  - refreshes the warehouse from existing raw tables
- `mm_shopify_raw_load_and_refresh_mvp`
  - loads current Shopify CSVs
  - rebuilds canonical raw tables
  - refreshes staging, marts, analysis, and validation

Useful CLI commands:

```bash
docker compose up airflow-init
docker compose up -d
docker compose down
docker compose down --remove-orphans
```

## Why this matters

This milestone improves the project in two important ways.

### Business / engineering value

The project now has a more stable local orchestration runtime for refreshing the warehouse from new Shopify CSV exports.

That makes it easier to continue using the warehouse as a real business decision-support system for Mischief Made.

### Portfolio quality

The repo now demonstrates a more realistic analytics engineering workflow:

- Dockerized local orchestration
- Airflow 3
- Postgres-backed metadata
- BigQuery execution
- local source-file ingestion
- raw landing and canonical rebuild
- downstream warehouse refresh
- machine-readable validation gates

This is a stronger platform signal than a standalone local Airflow process.

## Next likely steps

With Docker Compose orchestration now working, the next major directions could include:

- operational documentation cleanup
- `.env.example` for documenting local-only configuration
- Makefile or helper scripts for common Docker commands
- BI/dashboarding
- broader ingestion automation
- future multi-source integration:
  - Etsy
  - Faire
  - Etsy Ads
  - Pinterest Ads
- later migration toward dbt + Snowflake
