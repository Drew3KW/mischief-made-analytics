# Shopify API vs CSV Field Comparison Spike

## Summary

This note documents the first Shopify API field comparison for Milestone 27.

The goal of this spike is to understand whether Shopify Admin GraphQL API data can eventually replace or supplement the current Shopify CSV ingestion path.

This is intentionally a comparison note only.

No API-derived data is loaded into canonical BigQuery raw tables yet.

## Current baseline

The current known-good ingestion path is still the local Shopify CSV pipeline.

Current pipeline:

```text
Shopify CSV exports
  -> local_data/shopify/*.csv
  -> raw_load.shopify_*_latest
  -> raw.shopify_*
  -> staging
  -> marts
  -> analysis
  -> validation
```

The current Airflow CSV ingestion DAG loads local Shopify CSV files from `local_data/shopify`, lands them in `raw_load`, rebuilds canonical `raw`, then refreshes staging, marts, analysis, and validation. Orders are loaded with original CSV headers preserved, while customers and products are loaded with sanitized snake_case headers. :contentReference[oaicite:0]{index=0}

This CSV path remains the fallback and should not be removed until API-derived data has been reconciled against existing warehouse outputs.

## API spike status

The Shopify API spike has successfully proven:

- Docker Airflow can receive Shopify credentials from local `.env`
- Airflow can request a Shopify Admin API access token
- the access token has the required initial read scopes:
  - `read_orders`
  - `read_products`
  - `read_customers`
- Airflow can call the Shopify Admin GraphQL API
- Airflow can extract small samples of:
  - shop info
  - orders
  - products
  - customers
- Airflow can write local JSON sample files to:
  - `local_data/shopify_api_spike/`
- a helper script can generate a local field inventory from those JSON files
- the expanded `orders_sample.json` inventory now contains 213 field paths

This confirms that API extraction is viable enough to continue the spike.

## Current API sample files

Local-only files:

```text
local_data/shopify_api_spike/shop_connection_test.json
local_data/shopify_api_spike/orders_sample.json
local_data/shopify_api_spike/products_sample.json
local_data/shopify_api_spike/customers_sample.json
local_data/shopify_api_spike/field_inventory.md
```

These files should not be committed because they can contain real store, order, customer, and financial data.

## Current CSV-derived staging shape

### Order-item grain

Current CSV-derived order item staging model:

```text
staging.stg_shopify_order_items
```

Current grain:

```text
one row per order line item
```

Important fields currently derived from the Shopify orders CSV include:

| Current staging field | CSV source / meaning |
|---|---|
| `shopify_order_id` | Shopify order ID |
| `order_number` | customer/business-facing order number from `Name` |
| `sku` | line item SKU |
| `product_name` | line item name |
| `customer_email` | normalized email |
| `created_at_ts` | order created timestamp |
| `paid_at_ts` | paid timestamp |
| `fulfilled_at_ts` | fulfilled timestamp |
| `cancelled_at_ts` | cancelled timestamp |
| `financial_status` | order financial status |
| `fulfillment_status` | order fulfillment status |
| `lineitem_fulfillment_status` | line item fulfillment status |
| `currency` | order currency |
| `order_source` | source/channel |
| `risk_level` | risk level |
| `quantity` | line item quantity |
| `lineitem_price` | line item unit price |
| `compare_at_price` | compare-at price |
| `lineitem_discount` | line item discount |
| `order_subtotal` | order subtotal |
| `order_shipping` | order shipping |
| `order_taxes` | order taxes |
| `order_total` | order total |
| `order_discount_amount` | order-level discount |
| `refunded_amount` | refunded amount |
| `vendor` | product vendor |
| `billing_city` | billing city |
| `billing_province` | billing province |
| `billing_country` | billing country |
| `shipping_city` | shipping city |
| `shipping_province` | shipping province |
| `shipping_country` | shipping country |
| `payment_method` | payment method |
| `shipping_method` | shipping method |
| `tags` | order tags |

The current `stg_shopify_order_items` model is built from `raw.shopify_orders`, preserves line-item grain, casts raw string values into typed fields, and carries repeated order-level money fields on each line item. :contentReference[oaicite:1]{index=1}

### Order grain

Current CSV-derived order staging model:

```text
staging.stg_shopify_orders
```

Current grain:

```text
one row per order
```

This model rolls up line-item-grain CSV rows into order-level records by grouping on `order_number`, using `MAX()` for repeated order-level attributes and aggregate counts/sums for line-item metrics. :contentReference[oaicite:2]{index=2}

Current order-level fields include:

| Current staging field | Meaning |
|---|---|
| `shopify_order_id` | Shopify order ID |
| `order_number` | practical business-facing order key |
| `customer_email` | normalized customer email |
| `created_at_ts` | order created timestamp |
| `paid_at_ts` | paid timestamp |
| `fulfilled_at_ts` | fulfilled timestamp |
| `cancelled_at_ts` | cancelled timestamp |
| `financial_status` | financial status |
| `fulfillment_status` | fulfillment status |
| `currency` | order currency |
| `order_source` | source/channel |
| `risk_level` | risk level |
| `order_subtotal` | subtotal |
| `order_shipping` | shipping |
| `order_taxes` | taxes |
| `order_total` | total |
| `order_discount_amount` | discount |
| `refunded_amount` | refunded amount |
| `total_items` | sum of line item quantities |
| `line_item_count` | count of order lines |
| `distinct_sku_count` | distinct SKU count |
| `billing_city` | billing city |
| `billing_province` | billing province |
| `billing_country` | billing country |
| `shipping_city` | shipping city |
| `shipping_province` | shipping province |
| `shipping_country` | shipping country |
| `payment_method` | payment method |
| `shipping_method` | shipping method |
| `tags` | tags |

### Current marts dependency

The current `marts.fct_order_items` model depends on line-item-grain fields such as `order_number`, `sku`, `product_name`, `customer_email`, order timestamps, quantity, line item price, discount, vendor, geography, shipping method, payment method, and tags. It generates `order_item_key`, keeps `product_key` at item grain, and calculates item revenue fields. :contentReference[oaicite:3]{index=3}

The current `marts.fct_orders` model depends on `staging.stg_shopify_orders` and preserves order-level money, customer, status, geography, and trusted-date anomaly flags. :contentReference[oaicite:4]{index=4}

## API-to-current-warehouse mapping

### Order identity and dates

| Current field | API candidate field | Status |
|---|---|---|
| `shopify_order_id` | `orders.edges[].node.legacyResourceId` or parsed numeric value from `id` | Needs query expansion |
| `order_number` | `orders.edges[].node.name` | Good match |
| `created_at_ts` | `orders.edges[].node.createdAt` | Good match |
| `paid_at_ts` | likely transaction/payment data or `processedAt` depending business definition | Needs investigation |
| `fulfilled_at_ts` | fulfillment data, not yet queried | Needs query expansion |
| `cancelled_at_ts` | `orders.edges[].node.cancelledAt` | Good match |
| `updated_at_ts` | `orders.edges[].node.updatedAt` | Additional useful field |

Notes:

- `order_number` should continue to use Shopify order `name`, since that matches the current practical business-facing order key.
- API `id` is a GraphQL global ID, not the same shape as the integer ID currently cast from CSV.
- Add `legacyResourceId` in the next API query version to preserve a cleaner numeric Shopify order ID.

### Customer identity

| Current field | API candidate field | Status |
|---|---|---|
| `customer_email` | `orders.edges[].node.email` or `orders.edges[].node.customer.email` | Good match |
| customer ID | `orders.edges[].node.customer.id` | Available |
| customer display name | `orders.edges[].node.customer.displayName` | Available |

Notes:

- Continue treating `customer_email` as the practical customer key for current warehouse compatibility.
- API customer ID can become an additional durable Shopify-native identifier, but should not replace `customer_email` immediately.

### Order statuses

| Current field | API candidate field | Status |
|---|---|---|
| `financial_status` | `displayFinancialStatus` | Good match |
| `fulfillment_status` | `displayFulfillmentStatus` | Good match |
| `lineitem_fulfillment_status` | not currently queried | Needs investigation |
| `risk_level` | `risk` / risk summary fields | Needs query expansion |

Notes:

- The API fields are display-oriented enum values, not necessarily identical strings to CSV values.
- Before replacing CSV logic, compare distinct status values from API vs CSV.

### Order-level money

| Current field | API candidate field | Status |
|---|---|---|
| `order_subtotal` | `subtotalPriceSet.shopMoney.amount` or `currentSubtotalPriceSet.shopMoney.amount` | Available |
| `order_shipping` | `totalShippingPriceSet.shopMoney.amount` or `currentShippingPriceSet.shopMoney.amount` | Available |
| `order_taxes` | `totalTaxSet.shopMoney.amount` or `currentTotalTaxSet.shopMoney.amount` | Available |
| `order_total` | `totalPriceSet.shopMoney.amount` or `currentTotalPriceSet.shopMoney.amount` | Available |
| `order_discount_amount` | `totalDiscountsSet.shopMoney.amount` or `currentTotalDiscountsSet.shopMoney.amount` | Available |
| `refunded_amount` | `totalRefundedSet.shopMoney.amount` | Available |
| additional payment context | `netPaymentSet`, `totalReceivedSet` | Available |

Notes:

- The API provides both original and current financial values.
- This is better than the CSV in some ways, but it requires a deliberate business definition.
- For initial compatibility with current warehouse outputs, prefer original order-created values where they map to current CSV fields.
- For refund-aware reporting, preserve current values separately rather than overwriting original values.

Shopify documents order-level money fields including `currentShippingPriceSet`, `currentSubtotalPriceSet`, `currentTotalDiscountsSet`, `currentTotalPriceSet`, `currentTotalTaxSet`, `subtotalPriceSet`, `totalDiscountsSet`, `totalPriceSet`, `totalRefundedSet`, `totalRefundedShippingSet`, `totalShippingPriceSet`, and `totalTaxSet`. :contentReference[oaicite:5]{index=5}

### Line-item identity and pricing

| Current field | API candidate field | Status |
|---|---|---|
| line item ID | `lineItems.edges[].node.id` | Available |
| `sku` | `lineItems.edges[].node.sku` or `variant.sku` | Available |
| `product_name` | `lineItems.edges[].node.title` or `name` | Available |
| `quantity` | `lineItems.edges[].node.quantity` | Available |
| current/refund-adjusted quantity | `lineItems.edges[].node.currentQuantity` | Available |
| `lineitem_price` | `originalUnitPriceSet.shopMoney.amount` | Available |
| `lineitem_discount` | `totalDiscountSet.shopMoney.amount` | Available |
| line item discounted unit price | `discountedUnitPriceSet.shopMoney.amount` | Available |
| line item discounted total | `discountedTotalSet.shopMoney.amount` | Available |
| line item taxes | `taxLines[].priceSet.shopMoney.amount` | Available |

Notes:

- The current warehouse calculates `gross_item_revenue` as `quantity * lineitem_price`.
- For compatibility, API `lineitem_price` should likely map to `originalUnitPriceSet.shopMoney.amount`.
- API `currentQuantity` should be preserved separately, because it excludes refunded and removed units.
- `totalDiscountSet` is likely the closest line-level discount candidate, but discount behavior should be validated against CSV.

Shopify documents line-item fields including `quantity`, `currentQuantity`, `sku`, `title`, `variant`, `originalUnitPriceSet`, `discountedUnitPriceSet`, `discountedTotalSet`, `originalTotalSet`, `taxLines`, and `totalDiscountSet`. :contentReference[oaicite:6]{index=6}

### Product fields

| Current concept | API candidate field | Status |
|---|---|---|
| product ID | `products.edges[].node.id` | Available |
| product title | `products.edges[].node.title` | Available |
| product handle | `products.edges[].node.handle` | Available |
| vendor | `products.edges[].node.vendor` | Available |
| product type | `products.edges[].node.productType` | Available |
| status | `products.edges[].node.status` | Available |
| tags | `products.edges[].node.tags[]` | Available |
| variant ID | `variants.edges[].node.id` | Available |
| variant title | `variants.edges[].node.title` | Available |
| variant SKU | `variants.edges[].node.sku` | Available |
| variant price | `variants.edges[].node.price` | Available |
| inventory quantity | `variants.edges[].node.inventoryQuantity` | Available |

Notes:

- Product/variant API data is sufficient for a future products landing table.
- Historical product analysis should continue to account for deleted products and sold SKUs that may not exist in the current product catalog.
- Existing `dim_products_historical` logic remains important even if API product extraction improves current product coverage.

### Customer fields

| Current concept | API candidate field | Status |
|---|---|---|
| customer ID | `customers.edges[].node.id` | Available |
| customer email | `customers.edges[].node.email` | Available |
| first name | `customers.edges[].node.firstName` | Available |
| last name | `customers.edges[].node.lastName` | Available |
| display name | `customers.edges[].node.displayName` | Available |
| customer created timestamp | `customers.edges[].node.createdAt` | Available |
| customer updated timestamp | `customers.edges[].node.updatedAt` | Available |
| order count | `customers.edges[].node.numberOfOrders` | Available |
| default city | `customers.edges[].node.defaultAddress.city` | Available |
| default province | `customers.edges[].node.defaultAddress.province` | Available |
| default country | `customers.edges[].node.defaultAddress.country` | Available |
| default zip | `customers.edges[].node.defaultAddress.zip` | Available |

Notes:

- Customer API data is enough to support a future customer landing table.
- Continue using `customer_email` as the current practical analytical key for compatibility.
- Customer ID can be added as a durable Shopify-native identifier over time.

## Important semantic decisions before BigQuery landing

### 1. Original vs current order money

The API exposes both original and current financial fields.

Potential approach:

| Concept | API field family |
|---|---|
| original order-created amount | `subtotalPriceSet`, `totalPriceSet`, `totalDiscountsSet`, `totalTaxSet`, `totalShippingPriceSet` |
| current after refunds/edits/returns | `currentSubtotalPriceSet`, `currentTotalPriceSet`, `currentTotalDiscountsSet`, `currentTotalTaxSet`, `currentShippingPriceSet` |
| refund-specific amount | `totalRefundedSet`, `totalRefundedShippingSet` |
| payment-specific amount | `netPaymentSet`, `totalReceivedSet` |

Recommendation:

- Preserve both original and current fields in the API landing layer.
- Do not collapse them too early.
- Match current CSV-derived warehouse fields first, then add richer refund/current-state analysis later.

### 2. GraphQL IDs vs legacy IDs

GraphQL IDs look like globally unique IDs, for example:

```text
gid://shopify/Order/123456789
```

Current CSV staging casts `Id` into an integer `shopify_order_id`.

Recommendation:

- Add `legacyResourceId` to future order, product, variant, and customer queries where available.
- Preserve GraphQL IDs too.
- Use `order_number` as the business-facing order key for current compatibility.

### 3. Pagination

The current sample queries use small `first` values.

Future extraction must handle:

- order pagination
- product pagination
- customer pagination
- nested line item pagination
- nested product variant pagination

The current field inventory already confirms that Shopify returns `pageInfo.hasNextPage` and `pageInfo.endCursor` for top-level and nested connections.

### 4. Historical orders

The current API token can read recent orders.

Historical order backfill may require `read_all_orders`.

Shopify documents that only the last 60 days of orders are accessible by default, and older records require requesting access to all orders with the appropriate order scopes. :contentReference[oaicite:7]{index=7}

Recommendation:

- Do not block the spike on historical order access.
- Use recent orders first to prove shape and reconciliation mechanics.
- Treat `read_all_orders` as a later requirement for full replacement of the CSV historical pipeline.

### 5. Landing table design

Do not write API data directly into current canonical raw tables.

Preferred path:

```text
Shopify API
  -> raw_load/shopify_api_spike or dedicated API landing tables
  -> comparison layer
  -> reconciled canonical raw rebuild
  -> staging/marts/analysis
```

Possible future tables:

```text
raw_load.shopify_orders_api_latest
raw_load.shopify_products_api_latest
raw_load.shopify_customers_api_latest
```

Potentially later:

```text
raw.shopify_orders_api
raw.shopify_products_api
raw.shopify_customers_api
```

## Recommended next query additions

The current spike should add or confirm these fields before designing API landing tables.

### Orders

Add or confirm:

```text
legacyResourceId
sourceName
paymentGatewayNames
billingAddress {
  city
  province
  country
  zip
}
shippingAddress {
  city
  province
  country
  zip
}
risk {
  recommendation
}
fulfillments {
  createdAt
  status
}
```

### Line items

Add or confirm:

```text
refundableQuantity
nonFulfillableQuantity
unfulfilledQuantity
product {
  id
  title
  handle
}
variant {
  id
  legacyResourceId
  sku
  title
}
```

### Products

Add or confirm:

```text
legacyResourceId
variants {
  legacyResourceId
}
```

### Customers

Add or confirm:

```text
legacyResourceId
```

## Current conclusion

The Shopify Admin GraphQL API appears viable as a future source for automated ingestion.

The API now covers the most important current warehouse concepts:

- order number
- customer email
- order timestamps
- order status
- order-level money
- refunds
- shipping
- taxes
- line item quantity
- line item SKU
- line item price
- line item discount
- product/variant identity
- customer identity

However, the API should not replace the CSV pipeline yet.

The next safe step is to expand the API sample query with legacy IDs, addresses, source/payment fields, risk fields, and fulfillment fields, then generate a second inventory and compare the API-derived sample against the current CSV-derived staging shape.

## Recommendation

Proceed with the API spike in parallel with the CSV pipeline.

Do not change canonical raw rebuild logic yet.

Do not change marts or analysis models yet.

Use the next milestone slice to answer:

```text
Can API sample fields reproduce the current order and line-item staging models closely enough to design API landing tables?
```