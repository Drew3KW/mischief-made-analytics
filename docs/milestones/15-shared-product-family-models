# Milestone 15 - Shared Product Family Models and Family Analysis Refactor

## Objective

Promote product-family assignment logic into shared reusable marts models and refactor existing family analysis to use those shared models.

This phase creates:
- `marts.product_family_map`
- `marts.dim_product_families`

It also refactors existing family-level analysis views so product-family assignment and canonical family naming are no longer repeatedly derived downstream.

---

## Why this work was done now

Product-family logic began as downstream analysis logic, but it had become a recurring semantic dependency across the project.

By this point, product-family assignment was already central to:
- product-family performance analysis
- monthly family revenue trends
- recent family trend classification
- planned customer x product-family mix analysis

Because the same family assignment and canonical naming logic was being repeated in multiple places, this became the right moment to move that logic upstream into shared modeled objects.

This is a warehouse-design improvement, not just a convenience refactor.

---

## Deliverables

### Shared marts models
- `sql/marts/product_family_map.sql`
- `sql/marts/dim_product_families.sql`

### Refactored analysis models
- `sql/analysis/product_performance_by_family.sql`
- `sql/analysis/product_revenue_monthly_by_family.sql`

### Retired analysis model
- `sql/analysis/product_revenue_monthly_by_family_untrusted_dates.sql`

### Validation
- `sql/validation/product_family_models_validation.sql`

---

## Model design

### `marts.product_family_map`
**Grain:** one row per `product_key`

Purpose:
- maps each product to a derived `product_family_key`
- stores family assignment method
- stores cleaned and canonical family naming information for downstream reuse

Why it exists:
- `fct_order_items` correctly stores `product_key`, not `product_family_key`
- family assignment is derived business logic, not a base fact-table field
- downstream models need a reusable lookup from product to family

### `marts.dim_product_families`
**Grain:** one row per `product_family_key`

Purpose:
- stores the family once at family grain
- exposes canonical family name and lightweight family metadata
- supports downstream family-level analysis without repeating family rollup logic

---

## Key modeling choices

### Keep `fct_order_items` at order-item grain
`fct_order_items` continues to store `product_key` as the correct foreign key at order-item grain.

`product_family_key` was not added to the fact table because it is derived semantic logic rather than a base fact-table identifier.

### Centralize family assignment logic
The project’s family-key derivation rules remain based on:
- SKU-derived family keys when SKU is specific enough
- normalized product-name family keys when SKU is missing or too generic
- fallbacks that avoid over-grouping generic items like stickers, greeting cards, pins, magnets, totes, and similar categories

### Centralize canonical naming
Canonical family naming now lives in shared family models instead of being recomputed in every downstream analysis view.

### Use trusted dates by default
Trusted dates are now the default standard for business-facing family analysis.

The untrusted monthly family revenue model was useful during anomaly investigation, but it no longer serves an ongoing business purpose and was retired from the active analysis layer.

---

## Refactor outcome

Existing family-level analysis now uses shared product-family models instead of embedding family derivation logic inline.

This makes downstream models:
- shorter
- easier to read
- easier to maintain
- easier to extend

It also means future family-definition changes can be handled in one shared place rather than across multiple analysis views.

---

## Why this matters

This change improves the warehouse in several ways:

- reduces repeated regex and business logic in downstream views
- creates a reusable semantic family layer
- makes future analysis models easier to write and maintain
- makes family-definition changes easier to manage in one place
- better separates reusable warehouse logic from analysis-specific logic

This is especially important because product-family analysis has become a major axis of the project.

---

## Validation performed

- validated one row per `product_key` in `product_family_map`
- validated one row per `product_family_key` in `dim_product_families`
- tied out row count in `product_family_map` to `dim_products_historical`
- confirmed all dimension family keys exist in the map

---

## Outcome

The warehouse now has a reusable shared product-family layer.

This lays the groundwork for:
- cleaner downstream family analysis
- customer x product-family mix analysis
- future dashboard-ready family summary models
- easier long-term maintenance of family logic
