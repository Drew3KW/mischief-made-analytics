# Milestone 52: Product & Channel Profitability MVP

## Summary

Milestone 52 turns the Milestone 51 COGS foundation into business-facing product and channel profitability reporting.

The milestone adds monthly profitability KPIs, product-family rankings, month-over-month channel trends, and a COGS coverage audit. All profitability metrics remain estimated gross product profitability before fees rather than accounting net profit.

## Scope

This milestone adds:

* Monthly profitability KPIs by channel
* Product-family profitability rankings
* Qualified gross-margin rankings
* Monthly channel profitability trends
* Conservative month-over-month comparisons
* Recent-versus-historical COGS coverage auditing
* Product-family source-key lineage
* Permanent Milestone 52 validation
* Airflow orchestration for the new models and validation

## Analysis Views

### `marts.anl_profitability_kpi_summary`

Provides monthly channel KPIs including:

* Net item revenue before refunds
* Revenue with accepted COGS
* Estimated item COGS
* Estimated gross profit before fees
* Estimated gross margin before fees
* Accepted COGS revenue coverage
* Profitability coverage status

Ratios are recalculated after aggregation rather than averaged from lower-grain rows.

### `marts.anl_product_profitability_rankings`

Provides one reporting row per channel and exact product-family name.

The view:

* Consolidates legacy and size-specific source keys for reporting
* Preserves contributing source keys in lineage fields
* Keeps unknown product families visible
* Ranks families by accepted-COGS revenue and estimated gross profit
* Preserves a raw gross-margin rank
* Adds a qualified gross-margin rank for commercially meaningful rows

Qualified margin ranking requires:

* Positive accepted-COGS revenue
* At least 70% accepted-COGS revenue coverage
* At least five orders
* At least five units sold

This prevents one-off transactions, negative revenue, and weak-coverage rows from dominating the business-facing margin leaderboard.

### `marts.anl_channel_profitability_monthly`

Provides channel-level monthly trends and month-over-month changes.

Month-over-month metrics are populated only when:

* The previous available row is the immediately preceding calendar month
* The current reporting month is complete

Current partial months and calendar gaps remain visible but do not receive misleading change metrics.

### `marts.anl_product_profitability_coverage_audit`

Provides a maintenance-oriented view of COGS quality by channel and product family.

The view separates:

* Accepted COGS
* Missing COGS
* Missing SKU
* Review conflicts
* Manual exclusions
* Unrecognized statuses

It compares the most recent 12 completed calendar months with older historical data and preserves dynamic reporting-period boundaries in the output.

## Reporting Consolidation

Legacy Shopify and Etsy product-family keys sometimes differ because of size suffixes, abbreviations, naming changes, or inconsistent SKU conventions.

The rankings and coverage-audit views consolidate exact product-family names for reporting while preserving:

* Source product-family key count
* Source product-family key array

This does not alter source keys or force cross-channel identity matches.

## Manual Exclusions

The private product-family override file was expanded to cover known gift-card and mystery-box key variants.

These rows now resolve as:

* `excluded_from_profit_model`
* `manual_exclusion`

rather than appearing as missing COGS or missing SKU.

The override CSV remains private and outside version control.

## Validation

New validation:

* `sql/validation/product_profitability_mvp_validation.sql`

The validation script checks:

* Model grains
* Source-key lineage
* Margin-ranking eligibility
* Qualified-rank behavior
* Monthly source preservation
* Calendar comparison flags
* Month-over-month arithmetic
* Coverage reporting boundaries
* COGS row and revenue partitions
* Coverage-ratio arithmetic
* Coverage-status logic
* Issue flags
* Recognized COGS statuses
* Intentional exclusion handling
* Accepted-COGS profitability values

The complete validation script returned all `PASS` rows.

## Airflow

`mm_bigquery_refresh_mvp` now creates the four Milestone 52 analysis views and runs the new validation task.

Dependencies ensure:

* The KPI summary follows the existing monthly profitability model
* The channel trend view follows the KPI summary
* Rankings and coverage auditing follow the cross-channel item fact
* Milestone 52 validation waits for all four analysis views
* Profitability-foundation validation completes before Milestone 52 validation

A final manually triggered DAG run completed successfully with all tasks green.

## Semantic Boundary

Profitability remains estimated gross product profitability before:

* Channel fees
* Ad spend
* Shipping
* Labor
* Overhead
* Payout reconciliation
* Full accounting treatment

These metrics must not be described as net profit.

## Result

Milestone 52 provides a validated, dashboard-ready profitability layer that helps identify high-performing product families, compare channel trends, evaluate margin quality, and prioritize COGS maintenance without hiding uncertain or incomplete data.
