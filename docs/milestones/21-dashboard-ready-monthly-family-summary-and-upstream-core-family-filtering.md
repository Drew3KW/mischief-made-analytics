# 21 - Dashboard-Ready Monthly Family Summary and Upstream Core-Family Filtering

## Summary
This milestone adds the final planned summary-layer artifact for Analysis Pack v1:

- `marts.anl_family_summary`

It also strengthens the shared product-family layer by moving the core-family / non-core-family concept upstream into reusable marts models.

## What changed

### New dashboard-ready summary model
Added:

- `sql/analysis/family_summary.sql`
- `sql/analysis/family_summary_review.sql`
- `sql/validation/family_summary_validation.sql`

This produces:

- `marts.anl_family_summary`

at grain:

- **one row per reporting_month per product_family_key**

### Upstream shared-family enhancement
Updated shared product-family models so they now carry reusable business-facing family inclusion metadata:

- `marts.product_family_map`
- `marts.dim_product_families`

New shared attributes include:

- `is_core_family`
- `family_reporting_category`
- `family_exclusion_reason`

### Downstream analysis refactor
Updated core family analysis models to filter through the shared upstream family metadata instead of repeating family-exclusion regex logic inline:

- `marts.anl_product_revenue_monthly_by_family`
- `marts.anl_product_family_customer_mix`
- `marts.anl_family_summary`

Core family models now filter with:

- `dpf.is_core_family = TRUE`

## Why this was needed

Analysis Pack v1 originally centralized family assignment and canonical family naming in shared marts models:

- `product_family_map`
- `dim_product_families`

That refactor solved repeated downstream family-key derivation and canonical naming problems.

However, a later issue surfaced during family summary review:
non-core families such as mystery boxes and gift cards were still appearing in business-facing family outputs.

This happened because:

- family assignment and naming had been centralized upstream
- but business-facing family inclusion / exclusion was still partly implemented downstream
- different family analysis views were therefore operating on slightly different family universes

That made the warehouse less consistent than intended.

## Design decision

The fix was to move the **core-family / non-core-family reporting rule upstream** into the shared family layer.

This preserves access to non-core families for on-demand analysis, while allowing business-facing summary and core analysis models to exclude them consistently by default.

### Core principle
- **Shared marts models define family identity and reporting eligibility**
- **Downstream business-facing analysis models reuse that decision instead of re-implementing it**

## New upstream shared-family semantics

### `is_core_family`
Boolean flag used by business-facing family analysis and summary models.

- `TRUE` = include in core family reporting
- `FALSE` = exclude from core reporting by default

### `family_reporting_category`
Reusable classification such as:

- `core_merchandise`
- `non_core_mystery_box`
- `non_core_gift_item`
- `non_core_accessory_or_promo`

### `family_exclusion_reason`
A more specific machine-readable reason for exclusion, such as:

- `mystery_box`
- `gift_item`
- `sticker`
- `decal`
- `keychain`
- `greeting_card`
- `pin`
- `patch`
- `magnet`

## Dashboard-ready family summary

### Model
- `marts.anl_family_summary`

### Grain
- one row per `reporting_month` x `product_family_key`

### Key metrics
The model includes:

- monthly family revenue
- monthly orders containing the family
- monthly units sold
- monthly customers buying the family
- new vs returning customer counts
- family share of month revenue / orders / customers / units
- average order value for family
- average units per order
- revenue per family customer
- prior-month revenue, order, and customer comparisons
- monthly trend status and BI-friendly tier fields

### Data quality posture
- trusted dates are default
- cancelled / voided orders are excluded
- suspect historical timing rows are excluded
- only core families are included in business-facing family summary outputs

## Validation approach

Validation checks were added for:

- grain integrity
- null key checks
- revenue / unit / order tieout to monthly family revenue source
- monthly distinct customer tieout to source orders
- monthly net family revenue tieout to source lines
- share-of-month reconciliation
- new + returning customer reconciliation
- rate sanity checks
- negative metric sanity checks
- trend classification sanity checks
- explicit assertion that non-core families do not appear in `anl_family_summary`

## Business value

This milestone completes the planned summary layer for Analysis Pack v1 and improves the warehouse in two ways:

1. It adds a clean BI-facing monthly family summary for dashboarding.
2. It finishes the semantic refactor started earlier by making business-facing family eligibility a reusable upstream warehouse concept.

This makes downstream family analysis:

- more consistent
- easier to maintain
- less vulnerable to drift between views
- better aligned with future BI and dashboard work

## Next likely direction

With daily, monthly business, monthly customer, and monthly family summary layers now in place, the next major phase can reasonably move toward one or both of:

- BI / dashboard development
- ingestion / refresh scheduling
