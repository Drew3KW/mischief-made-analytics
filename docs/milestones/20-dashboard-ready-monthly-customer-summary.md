# 20 - Dashboard-Ready Monthly Customer Summary

## Summary
This milestone adds a dashboard-ready monthly customer summary layer to Analysis Pack v1 through:

- `marts.anl_customer_summary`
- `sql/analysis/customer_summary_review.sql`
- `sql/validation/customer_summary_validation.sql`

The new model gives BI a clean monthly rollup of customer mix, customer-base composition, lifecycle mix, and customer-focused revenue metrics.

## Why this was needed
By this point, the warehouse already had strong customer-grain analysis models:

- `anl_customer_order_behavior`
- `anl_customer_recency_segments`
- `anl_customer_cohort_retention`
- `anl_customer_rfm_segments`

However, dashboards still would have needed to compute too much customer logic themselves. A summary layer was needed to answer questions like:

- How many customers were active each month?
- How many were new vs returning?
- How is the customer base evolving over time?
- How much of the base is still one-time vs repeat vs loyal?
- How much of the base is active recent vs warming vs lapsed?
- How is the high-value customer mix changing month to month?

## Design choice
The key design decision was to make this model one row per `reporting_month`, rather than one row per customer.

That choice was made because:

1. customer-grain detail already existed upstream
2. this layer was intended for BI / dashboard use
3. monthly trend reporting is more useful for executive and business review
4. current-state recency / RFM views use `CURRENT_DATE()` logic and therefore are not appropriate for historical monthly aggregation

Instead, this model computes historically correct month-end customer snapshots from trusted completed orders in `fct_orders`.

## Grain
**One row per reporting month**

## Core metric groups
### Monthly activity
- customers with completed orders
- new customers
- returning customers
- monthly customer revenue

### Month-end customer base
- total customers acquired to date
- one-time customers
- repeat customers
- loyal customers

### Month-end lifecycle / value mix
- active recent customers
- warm customers
- cooling off customers
- lapsed customers
- high-value customers
- mid-value customers
- low-value customers

### Flagship RFM-style counts
- loyal high-value customers
- recent one-time customers
- lapsed high-value customers

### BI-friendly rates / averages
- pct new customers
- pct returning customers
- repeat customer rate
- loyal customer rate
- active customer rate
- average lifetime value across customer base
- average completed orders per customer base
- revenue per active customer

### Trend fields
- prior-month customer base
- prior-month active customers
- prior-month customer revenue
- month-over-month deltas and pct deltas

## Validation approach
Validation checks were added for:

- grain integrity
- null month checks
- tieout to `anl_monthly_business_summary` for active/new/returning/revenue metrics
- month-end customer-base tieout back to trusted completed orders
- segment reconciliation checks
- rate sanity checks
- negative metric checks

## Business value
This milestone improves the warehouse in two ways:

1. It makes customer reporting much easier in BI tools.
2. It demonstrates a stronger analytics engineering pattern: historically correct point-in-time customer snapshots, not just flat aggregations.

This is especially useful for future dashboarding and for later cross-channel customer analysis when additional sources are integrated.
