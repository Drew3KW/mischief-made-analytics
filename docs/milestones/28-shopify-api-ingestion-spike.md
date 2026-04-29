# 28 - Shopify API Ingestion Spike

## Summary

This milestone explored direct Shopify Admin API extraction as a future supplement or replacement for the current Shopify CSV ingestion path.

The goal was to prove API access and extraction patterns safely, without changing the existing CSV pipeline or writing API-derived data into canonical BigQuery raw tables.

The spike succeeded.

## What changed

Added Shopify API environment support:

- `SHOPIFY_SHOP_DOMAIN`
- `SHOPIFY_ADMIN_API_VERSION`
- `SHOPIFY_API_CLIENT_ID`
- `SHOPIFY_API_CLIENT_SECRET`

Added a small Shopify API extraction DAG:

```text
dags/mm_shopify_api_extract_spike.py
```

This DAG:

- authenticates to Shopify from Dockerized Airflow
- extracts small GraphQL samples for shop info, orders, products, and customers
- writes local JSON files to `local_data/shopify_api_spike/`
- does not write to BigQuery

Added a local sample inspection helper:

```text
scripts/inspect_shopify_api_samples.py
```

This script generates a local field inventory from the API sample JSON files.

Added a spike note:

```text
docs/spikes/27-shopify-api-vs-csv-field-comparison.md
```

This note documents how Shopify API fields compare to the current CSV-derived warehouse shape.

Added a Shopify Bulk Operation proof-of-concept DAG:

```text
dags/mm_shopify_bulk_operation_spike.py
```

This DAG:

- starts a Shopify Bulk Operation for products and variants
- polls until completion
- downloads the JSONL result locally
- generates a local summary
- does not write to BigQuery

## Validation

Validated `mm_shopify_api_extract_spike`:

- Shopify API credentials were loaded from local `.env`
- Airflow successfully requested a Shopify access token
- shop, order, product, and customer sample queries succeeded
- local JSON sample files were created
- field inventory generation succeeded
- expanded order sample inventory reached 283 field paths

Validated `mm_shopify_bulk_operation_spike`:

- product Bulk Operation started successfully
- polling completed successfully
- JSONL result downloaded locally
- local summary generated successfully

Bulk Operation result:

```text
Total JSONL lines: 3107
Product: 671
ProductVariant: 2436
```

## Design decisions

The current CSV ingestion pipeline remains the known-good fallback.

This milestone intentionally does not:

- replace CSV ingestion
- write Shopify API data to BigQuery
- modify canonical `raw.shopify_*` tables
- modify staging, marts, analysis, or validation logic
- introduce scheduled API ingestion

Preferred migration path:

```text
Shopify API
  -> isolated API landing tables
  -> API-vs-CSV comparison layer
  -> eventual canonical raw rebuild
```

## Local-only outputs

The following files/folders are local scratch outputs and should not be committed:

```text
.env
local_data/shopify_api_spike/
local_data/shopify_bulk_spike/
keys/
logs/
```

## Result

Shopify API ingestion is technically viable inside the current Dockerized Airflow environment.

The project now has working local proof-of-concept paths for:

```text
Docker Airflow
  -> Shopify Admin GraphQL API
  -> local JSON samples
  -> local field inventory
```

and:

```text
Docker Airflow
  -> Shopify Bulk Operation
  -> local JSONL export
  -> local summary
```

## Next step

Recommended next milestone:

```text
28 - Shopify API Landing MVP
```

Suggested goal:

```text
Write Shopify API-derived products and product variants into isolated BigQuery landing tables without replacing canonical raw tables.
```

Likely first tables:

```text
raw_load.shopify_products_api_latest
raw_load.shopify_product_variants_api_latest
```
