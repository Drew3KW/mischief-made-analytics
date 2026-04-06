# Milestone 18 - Dashboard-Ready Daily KPI Summary

## Objective

Add the first dashboard-ready KPI / summary model to Analysis Pack v1.

This phase creates a reusable one-row-per-day business summary view that consolidates core daily performance metrics into a clean BI-friendly layer.

---

## Why this work was done now

By this point, the warehouse already supported:

* reusable customer analysis
* product-family analysis
* customer lifecycle / retention analysis
* product-family customer behavior analysis

The next logical step was to begin the summary layer that sits between detailed analysis models and future BI dashboards.

This milestone starts that layer with a daily KPI view that helps answer questions such as:

* how much revenue did the business generate each day?
* how many orders were submitted, completed, and cancelled?
* how many customers purchased each day?
* how many of those customers were new vs returning?
* how many units were sold each day?
* what did cancellation and refund rates look like over time?

---

## Deliverables

### Analysis view

* `sql/analysis/daily_kpi_summary.sql`

### Review queries

* `sql/analysis/daily_kpi_summary_review.sql`

### Validation

* `sql/validation/daily_kpi_summary_validation.sql`

---

## Model design

### Grain

One row per `order_date`.

### Source of truth

The model is built primarily from:

* `marts.fct_orders`
* `marts.fct_order_items`

### Key outputs

The model includes:

* `order_date`
* `submitted_orders`
* `completed_orders`
* `cancelled_orders`
* `units_sold`
* `customers_submitting_orders`
* `customers_with_completed_orders`
* `new_customers`
* `returning_customers`
* `gross_revenue`
* `refunded_amount`
* `net_revenue_after_refunds`
* `avg_order_value`
* `cancellation_rate`
* `refund_rate`
* `avg_units_per_order`
* `revenue_per_completed_customer`

---

## Important modeling choices

### Build a clean summary layer before BI

This model is intentionally designed as a dashboard-ready summary view rather than a deep-dive analysis model.

That keeps BI logic lighter and makes it easier to build stable dashboard metrics on top of a consistent daily business grain.

### Use trusted dates by default

Business-facing analysis now assumes trusted-date filtering by default.

This view follows that standard by excluding suspect historical timing rows rather than relying on suffix-based naming.

### Separate submitted, completed, and cancelled orders

The summary distinguishes:

* all submitted orders
* completed non-cancelled orders
* cancelled orders

This provides a more accurate daily operational picture than collapsing all order activity into a single order count.

### Identify new vs returning customers from first completed order date

New vs returning customer counts are derived using each customer’s first trusted completed order date.

This keeps customer classification aligned with the project’s broader customer behavior standards.

### Keep the first KPI layer simple

This milestone focuses on foundational daily business KPIs rather than trying to embed deeper customer segmentation or family-level analysis into the same table.

That keeps the summary layer clean and makes later monthly, customer, and family summaries easier to build.

---

## Validation performed

### Structural checks

* validated one row per `order_date`
* validated no null dates

### Metric tieouts

* tied daily order counts back to `fct_orders`
* tied daily revenue metrics back to `fct_orders`
* tied daily unit metrics back to `fct_order_items`

### Sanity checks

* validated `new_customers + returning_customers = customers_with_completed_orders`
* validated cancellation and refund rates stay within expected bounds
* validated no unexpected negative values in core additive metrics

### Review checks

* reviewed recent daily KPI trends
* reviewed top revenue days
* reviewed top order-volume days
* reviewed cancellation and refund outliers
* reviewed monthly rollups derived from the daily summary
* reviewed simple seasonality patterns across month-of-year

---

## Outcome

This phase adds the first dashboard-ready summary layer to the project.

It is valuable for the business because it supports:

* daily business monitoring
* executive KPI tracking
* monthly rollups
* cleaner future dashboards

It is valuable for the portfolio project because it demonstrates:

* a semantic layer between warehouse facts and BI
* clear grain discipline
* metric definition and validation
* transition from analysis models into dashboard-ready reporting

---

## Relationship to prior work

This milestone builds directly on:

* `fct_orders`
* `fct_order_items`
* customer behavior modeling
* customer lifecycle / retention analysis
* product-family analysis

Together, these layers now support:

* detailed business analysis
* customer and family deep-dives
* early semantic summary modeling for BI consumption

---

## Current status

Completed:

* daily KPI summary view
* business-facing review queries
* validation queries for daily KPI reporting

Likely next steps:

* monthly business summary
* customer summary
* family summary
* BI dashboarding
