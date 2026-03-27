# Analysis Pack v1 - Customer Order Behavior

## Objective
Extend Analysis Pack v1 with a customer-level behavior view that supports repeat-customer analysis, average order value analysis, and first-pass cancellation / refund behavior analysis for Mischief Made.

This phase builds on the existing warehouse foundation and follows the repo’s current pattern of pairing analysis views with review queries and validation checks. :contentReference[oaicite:0]{index=0}

---

## Deliverables

### Analysis views
- `sql/analysis/customer_order_behavior.sql`

### Review queries
- `sql/analysis/customer_order_behavior_review.sql`

### Validation
- `sql/validation/customer_order_behavior_validation.sql`

---

## Business goal
The purpose of this work is to answer questions such as:
- how many customers are one-time vs repeat?
- what is average order value at the customer level?
- who are the highest-value customers?
- how common are cancellations and refunds by customer?
- which customers are most important to retain?

This is a natural next step after product-family analysis because it shifts Analysis Pack v1 from **what sells** toward **who is buying**. That makes the warehouse more useful both for real business decision support and as an analytics engineering portfolio project. :contentReference[oaicite:1]{index=1}

---

## Model design

### Grain
One row per nonblank `customer_email` with at least one order.

### Source of truth
The model is built from `marts.fct_orders`, using customer email as the business key for customer-level order behavior.

### Key outputs
The model includes:
- `customer_key`
- `customer_email`
- `first_order_date`
- `most_recent_order_date`
- `submitted_orders`
- `lifetime_orders`
- `cancelled_orders`
- `refunded_orders`
- `lifetime_revenue`
- `lifetime_refunded_amount`
- `lifetime_net_revenue_after_refunds`
- `avg_order_value`
- `customer_type`
- `cancellation_rate`
- `refund_rate`

Customer name fields are retained as descriptive attributes only. Customer email remains the trusted analytical key.

---

## Important modeling choices

### Completed-order logic
`lifetime_orders`, `lifetime_revenue`, `avg_order_value`, and `customer_type` are based on **non-cancelled orders**.

This avoids overstating customer value and avoids misclassifying customers as repeat buyers based on cancelled transactions.

### Submitted-order logic
`submitted_orders` is retained separately so cancellation behavior remains visible and measurable.

### Refund handling
The model includes both:
- gross completed-order revenue
- refunded amount
- net revenue after refunds

This makes the first customer behavior model immediately useful for both value and quality-of-revenue analysis.

### Customer identity
For this phase, `customer_email` is treated as the practical customer key. This is appropriate for the current Shopify-based warehouse and leaves room for later identity work if Etsy, Faire, or other channels are added.

---

## Source-data note
During review, customer `first_name` and `last_name` values appeared reversed for some customers but not others.

Follow-up checks showed:
- no duplicate / conflicting customer rows by email
- no evidence of a warehouse-wide field swap
- the same mixed pattern was visible upstream

This suggests inconsistent source name entry rather than a modeling bug. Since `customer_email` is the true analytical key, this issue does not materially affect customer behavior analysis.

---

## Validation performed

### Structural checks
- validated grain as one row per `customer_key`
- duplicate grain check returned 0 rows

### Tie-out checks
- total `lifetime_orders` tied out to distinct non-cancelled customer orders in `fct_orders`
- total `lifetime_revenue` tied out to non-cancelled customer order revenue in `fct_orders`
- total `submitted_orders` tied out to distinct customer orders in `fct_orders`

### Business sanity checks
- reviewed repeat vs one-time customer mix
- reviewed top customers by lifetime revenue
- reviewed AOV distribution bands
- reviewed customers with cancellation activity
- reviewed customers with refund activity

---

## Outcome
This phase adds the first customer-level analysis layer to Analysis Pack v1.

It is valuable for the business because it supports:
- repeat-customer analysis
- customer value analysis
- first-pass retention thinking
- refund and cancellation review

It is valuable for the portfolio project because it demonstrates:
- customer-grain modeling
- business-key selection
- metric definition discipline
- tie-out validation against fact data
- practical analysis-layer design for downstream BI and segmentation work

---

## Current status

Completed:
- customer order behavior analysis view
- business-facing customer review queries
- validation queries for customer behavior metrics

Likely next steps:
- customer recency / cohort analysis
- simple RFM-style segmentation
- product assortment / product-mix analysis by customer
- dashboard-ready customer summary views
