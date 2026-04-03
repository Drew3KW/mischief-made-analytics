# Milestone 16 - Product-Family Customer Mix Analysis

## Objective

Extend Analysis Pack v1 with a product-family customer mix view that connects product-family performance to customer behavior.

This phase adds a reusable business-facing analysis model that helps answer not just what product families sell, but what kinds of customers buy them.

---

## Why this work was done now

By this point in the project, the warehouse already supported:
- product-family performance analysis
- monthly family revenue trends
- recent family trend classification
- customer order behavior
- customer recency segmentation
- customer cohort retention

The next logical step was to connect the product and customer sides of the analysis layer.

This phase builds on the newly centralized shared product-family models and uses them to create a customer-aware family analysis view.

---

## Deliverables

### Analysis view
- `sql/analysis/product_family_customer_mix.sql`

### Review queries
- `sql/analysis/product_family_customer_mix_review.sql`

### Validation
- `sql/validation/product_family_customer_mix_validation.sql`

---

## Business goal

The purpose of this work is to answer questions such as:
- which product families attract the most unique customers?
- which families skew more heavily toward repeat customers?
- which families appear more often in customers’ first orders?
- which families are associated with higher-value customers?
- which families look more acquisition-oriented versus loyalty-oriented?

This extends the project from separate product and customer analysis into a more integrated merchandising and customer-behavior lens.

---

## Model design

### Grain
One row per `product_family_key`.

### Source of truth
The model is built from:
- `marts.fct_order_items`
- `marts.fct_orders`
- `marts.product_family_map`
- `marts.dim_product_families`
- `marts.anl_customer_order_behavior`

### Key outputs
The model includes:
- `product_family_key`
- `product_family_name`
- `customers_who_bought_family`
- `one_time_customers_who_bought_family`
- `repeat_customers_who_bought_family`
- `pct_repeat_customers`
- `orders_containing_family`
- `units_sold`
- `gross_family_revenue`
- `net_family_revenue_before_refunds`
- `avg_customer_lifetime_revenue`
- `avg_customer_lifetime_orders`
- `customers_first_buying_this_family`
- `pct_of_family_customers_first_buying_this_family`

---

## Important modeling choices

### Use shared product-family models
This view relies on:
- `product_family_map`
- `dim_product_families`

rather than re-deriving family logic inline.

This keeps product-family assignment and canonical naming centralized and reusable.

### Use trusted dates by default
The model includes only trusted completed-order activity.

It excludes:
- cancelled / voided orders
- suspect historical timing rows

This keeps product-family customer metrics aligned with the project’s current standard for business-facing analysis.

### Exclude non-core families for this analysis
Some real product families were intentionally excluded from this view because they are not analytically useful for customer-mix interpretation.

Excluded patterns include:
- mystery boxes
- stickers
- decals
- keychains
- greeting cards
- pins
- patches
- magnets

These remain valid products in the warehouse, but were filtered out here to keep the analysis focused on core merchandise families.

### First-purchase family logic
A customer’s “first-purchase family” is based on families present on the customer’s first trusted completed order timestamp.

This allows multiple families from the same first order to count as first-purchase families, which better reflects real order behavior than forcing a single-family assignment.

---

## Validation performed

### Structural checks
- validated one row per `product_family_key`
- confirmed all product families in the mix view exist in `dim_product_families`

### Customer mix checks
- validated that one-time plus repeat customer counts tied to total family customers
- validated that first-purchase-family customer counts did not exceed total family customers
- validated percentage fields stayed within the 0 to 1 range

### Revenue tieout
- tied total `gross_family_revenue` to trusted completed-order item revenue for the same included family population
- confirmed the final revenue diff was 0 after aligning validation exclusions to the view logic

### Review checks
- reviewed families with the most unique customers
- reviewed families with the highest repeat-customer share
- reviewed families most common in customers’ first orders
- reviewed families associated with higher-value customers
- reviewed acquisition-oriented and loyalty-oriented family patterns

---

## Outcome

This phase adds the first integrated product-family x customer-behavior analysis layer to Analysis Pack v1.

It is valuable for the business because it supports:
- more informed merchandising decisions
- stronger understanding of acquisition versus loyalty families
- better interpretation of what kinds of products attract different kinds of customers

It is valuable for the portfolio project because it demonstrates:
- semantic reuse of shared family models
- integration of product-grain and customer-grain logic
- analysis design around business questions rather than just source tables
- validation of cross-model rollups and revenue tieouts

---

## Relationship to prior work

This milestone builds directly on:
- the Shopify warehouse foundation
- historical product coverage work
- shared product-family models
- family-level product analysis
- customer behavior analysis
- recency segmentation
- cohort retention

Together, these layers now support analysis of:
- what products are selling
- which customers are buying
- how recently those customers have engaged
- whether customer cohorts return over time
- which families are associated with different customer patterns

---

## Current status

Completed:
- integrated product-family customer mix view
- business-facing review queries for customer-family patterns
- validation queries for product-family customer mix analysis

Likely next steps:
- simple RFM-style segmentation
- dashboard-ready KPI and summary layers
- BI/dashboarding
- ingestion / refresh workflow
