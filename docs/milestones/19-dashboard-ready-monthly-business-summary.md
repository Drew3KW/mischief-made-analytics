## Summary
Added a dashboard-ready monthly business summary view to Analysis Pack v1.

## What changed
- added `sql/analysis/monthly_business_summary.sql`
- added `sql/analysis/monthly_business_summary_review.sql`
- added `sql/validation/monthly_business_summary_validation.sql`
- added milestone doc:
  - `docs/milestones/19-dashboard-ready-monthly-business-summary.md`
- updated `README.md` to reflect the new monthly summary layer and revised next-step roadmap

## Model design
`marts.anl_monthly_business_summary` is built at one row per `order_month` and rolls up the validated daily KPI layer into a cleaner monthly business summary for BI and business review.

It includes:
- monthly order counts
- monthly customer counts
- new vs returning customer totals
- units sold
- gross revenue, refunded amount, and net revenue after refunds
- blended monthly KPI ratios
- month-over-month revenue, order, and customer comparisons

## Why
This extends the summary layer from daily KPI monitoring into monthly business reporting, supporting:
- month-to-month trend analysis
- business-owner reporting
- dashboard-ready monthly rollups
- easier interpretation of seasonality and growth patterns

## Validation
- confirmed one row per month
- tied additive monthly metrics back to `anl_daily_kpi_summary`
- validated recomputed blended KPI ratios
- validated new + returning customer sanity checks
- validated MoM lag fields
- reviewed monthly trends, best months, and customer mix outputs
