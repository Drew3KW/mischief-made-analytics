# Analysis Pack v1 - Customer Recency Segmentation

## Objective
Extend Analysis Pack v1 with a customer-level recency and lifecycle segmentation view that helps identify active, warming, cooling, and lapsed customers.

This phase builds directly on the customer order behavior layer and adds the first simple retention-oriented lens to the warehouse.

---

## Deliverables

### Analysis views
- `sql/analysis/customer_recency_segments.sql`

### Review queries
- `sql/analysis/customer_recency_segments_review.sql`

### Validation
- `sql/validation/customer_recency_segments_validation.sql`

---

## Business goal
The purpose of this work is to answer questions such as:
- which customers have ordered recently?
- which customers are drifting away?
- which customers appear to be lapsed?
- how much lifetime revenue is associated with each recency segment?
- which high-value customers may be worth re-engaging?

This is a natural next step after customer order behavior because it moves the project from static customer value analysis toward customer lifecycle and retention thinking.

---

## Model design

### Grain
One row per customer.

### Source of truth
The model is built from `marts.anl_customer_order_behavior`, which already provides customer-level order behavior metrics.

### Key outputs
The model includes:
- `customer_key`
- `customer_email`
- `first_order_date`
- `most_recent_order_date`
- `days_since_last_order`
- `lifetime_orders`
- `lifetime_revenue`
- `lifetime_net_revenue_after_refunds`
- `avg_order_value`
- `customer_type`
- `recency_segment`
- `value_segment`

---

## Important modeling choices

### Recency logic
Recency is measured as the number of days between `CURRENT_DATE()` and `most_recent_order_date`.

### Recency segments
Initial segment definitions were intentionally kept simple and business-readable:

- `active_recent`: 0 to 90 days since last order
- `warm`: 91 to 180 days
- `cooling_off`: 181 to 365 days
- `lapsed`: more than 365 days

These thresholds are meant to be practical starting points, not permanent final definitions.

### Value segmentation
A lightweight value segmentation field was included:
- `high_value`
- `mid_value`
- `lower_value`

This makes it easier to identify customers who are both valuable and at risk of lapsing, without yet building a full RFM framework.

---

## Validation performed

### Structural checks
- validated grain as one row per `customer_key`
- duplicate grain check returned 0 rows

### Tie-out checks
- row count tied out to `marts.anl_customer_order_behavior`
- total lifetime revenue tied out to `marts.anl_customer_order_behavior`

### Business sanity checks
- reviewed customer counts and revenue by recency segment
- reviewed recency segment by customer type
- reviewed top lapsed customers by lifetime revenue
- reviewed high-value active customers

---

## Outcome
This phase adds the first customer lifecycle layer to Analysis Pack v1.

It is valuable for the business because it supports:
- simple retention-oriented analysis
- prioritization of active vs lapsed customers
- identification of potentially valuable customers for re-engagement
- a more actionable understanding of the customer base than lifetime metrics alone

It is valuable for the portfolio project because it demonstrates:
- reuse of an existing semantic customer layer
- customer lifecycle modeling
- practical segmentation logic
- validation against upstream analysis models
- incremental construction of a business-facing analysis layer

---

## Relationship to prior work
This milestone builds directly on:
- the core Shopify warehouse foundation
- historical product coverage work
- product-family performance and trend analysis
- customer order behavior modeling

Together, these layers now support both:
- what products are selling
- which customers are buying
- how recently those customers have engaged

---

## Current status

Completed:
- customer recency segmentation view
- business-facing recency review queries
- validation queries for recency segmentation

Likely next steps:
- customer cohort / retention analysis
- simple RFM-style segmentation
- customer x product-family mix analysis
- dashboard-ready customer summary views
