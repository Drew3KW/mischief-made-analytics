# Milestone 48 - Business Dashboard MVP

## Summary

Milestone 48 created the first business-facing dashboard layer for Mischief Made.

The milestone adds a small set of dashboard-facing BigQuery views on top of the existing validated Shopify and Etsy revenue pipeline, wires those views into Airflow refresh DAGs, and validates them with a dedicated dashboard MVP validation query.

This milestone also produced the first Looker Studio dashboard MVP using the new dashboard contract layer.

## Goal

Create a clear, conservative BI surface for core business questions:

- How much revenue did the business generate?
- How many orders and units were sold?
- What is average order value?
- How does revenue split between Shopify and Etsy?
- Which Shopify product families drive revenue?
- What does Shopify customer health look like over time?

## Implemented Files

### Dashboard-facing analysis views

- `sql/analysis/dashboard_revenue_daily.sql`
- `sql/analysis/dashboard_revenue_monthly.sql`
- `sql/analysis/dashboard_channel_daily.sql`
- `sql/analysis/dashboard_product_family_summary.sql`
- `sql/analysis/dashboard_customer_health.sql`

### Validation

- `sql/validation/dashboard_mvp_validation.sql`

### Orchestration

Updated:

- `dags/mm_bigquery_refresh_mvp.py`
- `dags/mm_etsy_recent_refresh_mvp.py`
- `dags/mm_shopify_raw_load_and_refresh_mvp.py`

### Product-family cleanup

Updated:

- `sql/marts/product_family_map.sql`

## Dashboard Views

### `marts.anl_dashboard_revenue_daily`

Daily cross-channel dashboard KPI view.

Grain:

- One row per `order_date`

Includes:

- submitted orders
- completed orders
- cancelled orders
- Shopify completed orders
- Etsy completed orders
- channel-scoped customers
- refunded orders
- edge-case orders
- total units sold
- gross revenue
- refunded amount
- fee amount
- post-refund revenue
- channel-reported net amount
- Shopify revenue
- Etsy revenue
- AOV
- cancellation rate
- refund rate
- average units per order
- channel revenue share

### `marts.anl_dashboard_revenue_monthly`

Monthly cross-channel dashboard KPI view.

Grain:

- One row per `order_month`

Includes:

- monthly rollups from the daily dashboard view
- Shopify/Etsy monthly revenue split
- AOV
- monthly order counts
- month-over-month revenue change
- month-over-month order change

### `marts.anl_dashboard_channel_daily`

Daily long-format channel view for Looker Studio charts.

Grain:

- One row per `order_date`
- One row per `channel`

This view supports channel-based charts using `channel` as a dimension.

### `marts.anl_dashboard_product_family_summary`

Shopify-only product-family dashboard summary.

Grain:

- One row per Shopify `product_family_key`

This view is intentionally Shopify-only for Milestone 48. Cross-channel product-family harmonization is deferred.

The view is built from `marts.anl_family_summary`, which preserves the existing Milestone 21 convention that product-family identity and display naming are defined upstream.

### `marts.anl_dashboard_customer_health`

Shopify-only customer health dashboard summary.

Grain:

- One row per `reporting_month`

This view is intentionally Shopify-only for Milestone 48. Cross-channel customer identity resolution is deferred.

## Modeling Decisions

### Dashboard contract layer

Milestone 48 creates dashboard-facing views instead of connecting Looker Studio directly to lower-level marts and analysis views.

This gives the dashboard a stable BI contract while preserving the existing separation between:

- ingestion
- staging
- marts
- analysis
- dashboard outputs
- validation

### Primary revenue KPI

The dashboard uses `Post-Refund Revenue` as the primary cross-channel revenue KPI.

This is based on `total_net_revenue_after_refunds`, but the dashboard label avoids the vague term `Net Revenue`.

This distinction matters because:

- `Post-Refund Revenue` means revenue after refunds.
- It does not mean profit.
- It does not subtract COGS.
- It does not subtract ad spend.
- It does not fully reconcile payout/accounting net.
- Etsy fees are surfaced separately where available.

### Tax and payout reconciliation

Tax collected, marketplace-facilitator treatment, payout reconciliation, and full accounting net are not included in the executive dashboard scope.

Etsy and Shopify handle tax differently, and Etsy payment net can reflect deductions beyond visible Etsy fees. Those questions belong in later Etsy staging/marts and payout/accounting work.

### Product-family naming

A product-family display-name issue was discovered while building the dashboard. Some family names still included size-related suffixes such as `- Small`.

The fix was made upstream in `sql/marts/product_family_map.sql`, not inside the dashboard view.

This preserves the modeling principle from Milestone 21:

Product-family identity and display naming live upstream in shared marts, not inside dashboard-specific models.

### Shopify-only support pages

The Product Families and Customer Health dashboard pages are explicitly Shopify-only for this milestone.

Deferred:

- cross-channel product-family harmonization
- cross-channel customer identity resolution
- Etsy product/listing marts
- Etsy customer semantics

## Looker Studio Dashboard MVP

A first Looker Studio dashboard was created using these BigQuery views:

- `marts.anl_dashboard_revenue_daily`
- `marts.anl_dashboard_revenue_monthly`
- `marts.anl_dashboard_channel_daily`
- `marts.anl_dashboard_product_family_summary`
- `marts.anl_dashboard_customer_health`

Dashboard pages:

1. Executive Overview
2. Monthly Business Trend
3. Product Families
4. Customer Health

The dashboard remains a visualization layer. Semantic logic lives in BigQuery.

## Airflow Updates

### `mm_bigquery_refresh_mvp`

Updated to rebuild the dashboard-facing views as part of the main warehouse refresh.

Also now rebuilds `fct_cross_channel_orders` so cross-channel dashboard views can refresh as part of the main BigQuery refresh flow.

### `mm_etsy_recent_refresh_mvp`

Updated to rebuild cross-channel dashboard revenue views after Etsy recent refresh and latest-table promotion.

The DAG now validates:

- Etsy landing
- cross-channel revenue
- dashboard MVP outputs

### `mm_shopify_raw_load_and_refresh_mvp`

Updated to rebuild Shopify-only dashboard support views after the CSV fallback refresh flow.

This preserves CSV fallback support for Shopify product-family and customer-health dashboard views.

## Validation

The dashboard validation query checks:

- daily dashboard row shape
- monthly dashboard row shape
- channel daily row shape
- product-family dashboard row shape
- customer-health dashboard row shape
- daily dashboard totals against `fct_cross_channel_orders`
- monthly dashboard totals against daily dashboard totals
- channel daily totals against dashboard daily totals
- duplicate date/month/key checks
- invalid revenue share checks
- Shopify-only dashboard scope checks

Final validation result:

- `dashboard_mvp_validation.sql` returned no `FAIL` rows.

Airflow validation:

- `python -m py_compile` passed for updated DAGs.
- Airflow successfully imported the updated DAGs.
- `mm_bigquery_refresh_mvp` ran successfully.
- `mm_etsy_recent_refresh_mvp` ran successfully.

## Deferred

Milestone 48 does not implement:

- full Etsy staging/marts
- Etsy product/listing dimension modeling
- Etsy payout/accounting reconciliation
- cross-channel product-family harmonization
- cross-channel customer identity resolution
- COGS/profit modeling
- ad spend integration
- Faire integration

## Outcome

Milestone 48 establishes the first usable business dashboard MVP for Mischief Made.

The warehouse now has a dashboard-facing contract layer that supports executive revenue KPIs, channel performance, Shopify product-family performance, and Shopify customer health while keeping unresolved cross-channel semantics explicitly deferred.
