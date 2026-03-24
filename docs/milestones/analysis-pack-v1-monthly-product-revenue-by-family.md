# Analysis Pack v1 - Monthly Product Revenue by Family

## Objective

Extend Analysis Pack v1 with a monthly product family revenue view that supports time-series product analysis for Mischief Made.

This phase builds on the completed family-level product performance work and adds a monthly trend layer for product-family revenue.

---

## Deliverables

### Mart update
- Updated `sql/marts/fct_orders.sql`

Added:
- `is_suspect_historical_timing`
- `order_number_format`

These fields were introduced to identify a historical order-timestamp anomaly discovered during monthly trend validation.

### Analysis views
- `sql/analysis/product_revenue_monthly_by_family_untrusted_dates.sql`
- `sql/analysis/product_revenue_monthly_by_family_trusted_dates.sql`

### Validation
- `sql/validation/product_revenue_monthly_by_family_trusted_dates_validation.sql`

---

## Business goal

The purpose of this work is to answer questions such as:

- which product families are strongest month to month?
- which families show seasonality?
- which products are gaining or fading over time?

For apparel analysis, this is more useful at **product family** grain than at individual size-variant grain.

---

## Important issue discovered

While validating the first monthly family revenue view, a major anomaly appeared:

- January 2021 revenue was dramatically higher than every other month
- almost all orders in that month were concentrated on `2021-01-23`
- those orders shared the same `order_source`
- order identifiers in the raw `Name` field used a legacy long-numeric format rather than the later `#12345` format

Further inspection in Shopify Admin revealed:

- the `#` + 5 digit order-number format did not begin until `2021-01-31`
- older orders appear to have been affected by a bulk archival / migration / historical-system event around `2021-01-22` / `2021-01-23`
- pre-change orders consistently show timeline entries such as:
  - `This order was archived.`

This strongly suggests that many pre-`2021-01-31` orders do not have trustworthy `created_at` values for trend analysis.

---

## Modeling response

Rather than overwrite or guess historical order dates, the warehouse now distinguishes between:

### Untrusted full-history monthly trends
A monthly family view that includes all orders, even those with suspect historical timing.

This preserves full sales coverage for reference and debugging.

### Trusted-date monthly trends
A monthly family view that excludes orders flagged as suspicious for time-series interpretation.

This is the safer view for business-facing trend analysis.

---

## Flag logic added to `fct_orders`

`is_suspect_historical_timing = TRUE` when:
- `created_at_ts` is before `2021-01-31`
- or `created_at_ts` falls on the suspicious archival dates
- or `order_number` uses the older long-numeric format rather than the later `#12345` format

This allows downstream analysis to preserve historical orders while filtering unreliable order dates when needed.

---

## Validation performed

### Structural checks
- trusted monthly family view grain validated as one row per `order_month, product_family_key`
- duplicate grain check returned 0 rows

### Tie-out checks
- trusted monthly family revenue tied out to the trusted subset of fact data
- trusted monthly family units tied out to the trusted subset of fact data

### Historical anomaly investigation
- January 2021 spike traced back to `fct_orders`, not the analysis view
- daily inspection showed orders concentrated almost entirely on `2021-01-23`
- raw Shopify export inspection showed legacy order-name formatting for the anomalous batch
- Shopify Admin inspection suggested a bulk archival / migration event rather than real transaction timing

### Family-key cleanup
- continued to refine family-key normalization for historical name-based products
- removed trailing size markers where appropriate
- removed trailing artist-credit suffixes such as `_design_by_...` and `_art_by_...`

---

## Outcome

This phase produced a safer monthly product-family trend layer and surfaced an important source-data limitation.

This is valuable both for the business and for the portfolio project because it demonstrates:

- time-series validation
- anomaly detection
- source-system investigation
- careful handling of imperfect historical data
- separation of technically correct output from business-trustworthy output

---

## Current status

Completed:
- monthly product family revenue view
- trusted-date monthly product family revenue view
- `fct_orders` anomaly flagging
- validation and investigation of the historical timestamp anomaly

Likely next steps:
- dashboard-ready summary queries for top families by recent period
- variant drill-down views for size mix within family
- first business-facing insight memo based on trusted-date trends
