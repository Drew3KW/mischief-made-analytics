# Analysis Pack v1 - Product Family Performance

## Objective

Build the first business-facing product performance analysis for Mischief Made using marts only, with product reporting at the **family** level rather than the raw size-variant level.

This work supports both goals of the project:

1. produce useful business analysis for Mischief Made
2. strengthen the project as a portfolio-quality analytics engineering case study

---

## Why family grain was the right choice

Early in Analysis Pack v1, it became clear that raw product-variant analysis was not the right default grain for apparel performance reporting.

For business-facing analysis, the more useful question is usually:

- how did a **product/style** perform overall across all sizes?

rather than:

- how did an individual size variant perform in isolation?

Because of that, the primary analysis view for this phase was designed at **product family grain**.

---

## Deliverable built

### `marts.anl_product_performance_by_family`

Business-facing product performance view with one row per `product_family_key`.

Core metrics:
- `orders_containing_family`
- `units_sold`
- `gross_family_revenue`
- `avg_revenue_per_order_line`
- `first_order_date`
- `last_order_date`

Revenue definition used in this version:
- `gross merchandise revenue = quantity * lineitem_price`

Cancelled orders are excluded.

---

## Important modeling issue discovered during analysis

While validating the initial family-level rankings, the output surfaced a suspicious result:

- a single historical sticker product appeared to be an outsized bestseller

Initial inspection suggested the row might be incorrectly aggregating all historical sticker sales into one fake product.

Further investigation confirmed that this was a real mart-layer modeling problem, not just an analysis-layer issue.

### Root cause

`dim_products_historical` and `fct_order_items` were using SKU-based product keys whenever SKU was present.

That worked for most products, but some deleted historical items used **generic SKUs** such as:

- `sticker`
- `greeting card`

Because those SKUs were not specific enough to represent unique products, multiple distinct historical products collapsed into one shared `product_key`.

This caused misleading analysis results.

---

## Mart-layer fix implemented

The historical product-key logic was updated in both:

- `sql/marts/dim_products_historical.sql`
- `sql/marts/fct_order_items.sql`

### New rule

- if SKU is present **and specific**, use `SKU|<normalized sku>`
- if SKU is blank or **too generic**, use `NAME|<normalized product_name>`

This made product identity more conservative and prevented distinct historical products from being merged into fake mega-products.

---

## Family-rollup refinement implemented

After fixing the mart-layer product key issue, the family-level analysis was further refined.

### Additional issue discovered

Some deleted historical products were name-based rather than SKU-based, and their size information was embedded at the end of `product_name`, for example:

- `Twistin’ The Night Away Ringer Tshirt in White/Black - Art by Naoya - X-Large`

When normalized, these names were initially treated as separate families by size.

### Fix

The family-rollup logic in `sql/analysis/product_performance_by_family.sql` was updated to strip trailing size tokens from name-based historical products when deriving `product_family_key`.

Examples handled include:
- `x_large`
- `xx_large`
- `1x`
- `2x`
- `3x`
- `1x_large`
- `3x_large`
- `2xl`
- `3xl`

This improved family-level rollup quality for deleted historical apparel products.

---

## Validation performed

The following validations were run after the mart rebuild and analysis update:

- `dim_products_historical.product_key` remained unique
- `fct_order_items` row count still matched `stg_shopify_order_items`
- `fct_order_items.order_item_key` remained unique
- fact-to-dimension join coverage remained complete (`0` unmatched fact rows)
- source-type breakdown remained stable, indicating the fix was targeted rather than disruptive
- generic sticker/greeting-card collisions no longer appeared in misleading ways
- family-level revenue tied back to fact-level revenue
- remaining family keys ending in size tokens were checked for residual edge cases
- top family rankings were manually reviewed for business plausibility

---

## Outcome

This work produced the first trustworthy business-facing product family performance view for Analysis Pack v1.

It also uncovered and fixed a meaningful real-world data modeling issue:

- historical product identity can break down when source systems reuse generic SKUs
- business-facing analysis can reveal mart-layer modeling defects that are not obvious from structural validation alone

That made this phase especially valuable as a portfolio artifact because it demonstrates:

- source-aware modeling judgment
- iterative debugging
- dimensional modeling refinement
- business validation, not just technical validation

---

## Current status

Completed:
- mart-layer historical product-key fix
- family-level product performance view
- validation queries
- manual sanity review of top family rankings

Likely next steps:
- build `product_revenue_monthly_by_family`
- add supporting variant-level drill-down analysis
- begin deeper product-performance analysis and insight generation
