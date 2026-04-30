-- sql/analysis/shopify_api_csv_order_reconciliation.sql
-- Purpose:
-- Reconcile Shopify API order and line item landing data against the existing
-- CSV-derived order warehouse.
--
-- Grain:
-- One row per order number in the API-accessible order window.
--
-- Notes:
-- - This is comparison-only.
-- - This does not modify canonical raw tables.
-- - This does not replace the CSV ingestion path.
-- - This does not change staging, marts, or business-facing analysis logic.
-- - Current API order access may be limited to the recent-order window.

CREATE OR REPLACE VIEW `mischief-made-analytics.marts.anl_shopify_api_csv_order_reconciliation` AS

WITH
  api_orders AS (
    SELECT
      shopify_order_graphql_id,
      SAFE_CAST(legacy_resource_id AS INT64) AS api_shopify_order_id,
      order_number AS api_order_number,
      LOWER(TRIM(email)) AS api_normalized_email,
      email AS api_email,
      LOWER(TRIM(customer_email)) AS api_normalized_customer_email,
      customer_email AS api_customer_email,
      customer_graphql_id AS api_customer_graphql_id,
      SAFE_CAST(customer_legacy_resource_id AS INT64) AS api_customer_legacy_resource_id,
      created_at AS api_created_at_ts,
      processed_at AS api_processed_at_ts,
      updated_at AS api_updated_at_ts,
      cancelled_at AS api_cancelled_at_ts,
      LOWER(TRIM(display_financial_status)) AS api_financial_status_normalized,
      display_financial_status AS api_financial_status,
      LOWER(TRIM(display_fulfillment_status)) AS api_fulfillment_status_normalized,
      display_fulfillment_status AS api_fulfillment_status,
      currency_code AS api_currency,
      order_source AS api_order_source,
      SAFE_CAST(NULLIF(TRIM(current_subtotal_price), '') AS NUMERIC) AS api_order_subtotal,
      SAFE_CAST(NULLIF(TRIM(current_shipping_price), '') AS NUMERIC) AS api_order_shipping,
      SAFE_CAST(NULLIF(TRIM(current_total_tax), '') AS NUMERIC) AS api_order_taxes,
      SAFE_CAST(NULLIF(TRIM(current_total_price), '') AS NUMERIC) AS api_order_total,
      SAFE_CAST(NULLIF(TRIM(current_total_discounts), '') AS NUMERIC) AS api_order_discount_amount,
      SAFE_CAST(NULLIF(TRIM(total_refunded), '') AS NUMERIC) AS api_refunded_amount,
      billing_city AS api_billing_city,
      billing_province_code AS api_billing_province,
      billing_country_code AS api_billing_country,
      shipping_city AS api_shipping_city,
      shipping_province_code AS api_shipping_province,
      shipping_country_code AS api_shipping_country,
      payment_gateway_names_json AS api_payment_gateway_names_json,
      shipping_line_title AS api_shipping_method,
      tags_json AS api_tags_json
    FROM `mischief-made-analytics.raw_load.shopify_orders_api_latest`
  ),

  api_window AS (
    SELECT
      MIN(api_created_at_ts) AS api_min_created_at_ts,
      MAX(api_created_at_ts) AS api_max_created_at_ts
    FROM api_orders
  ),

  api_line_items AS (
    SELECT
      line_items.shopify_line_item_graphql_id,
      line_items.shopify_order_graphql_id,
      orders.order_number AS api_order_number,
      NULLIF(LOWER(TRIM(line_items.sku)), '') AS api_normalized_sku,
      line_items.sku AS api_sku,
      line_items.title AS api_product_name,
      line_items.quantity AS api_quantity,
      line_items.current_quantity AS api_current_quantity,
      SAFE_CAST(NULLIF(TRIM(line_items.original_unit_price), '') AS NUMERIC) AS api_original_unit_price,
      SAFE_CAST(NULLIF(TRIM(line_items.discounted_unit_price), '') AS NUMERIC) AS api_discounted_unit_price,
      SAFE_CAST(NULLIF(TRIM(line_items.discounted_total), '') AS NUMERIC) AS api_discounted_total,
      SAFE_CAST(NULLIF(TRIM(line_items.total_discount), '') AS NUMERIC) AS api_total_discount
    FROM `mischief-made-analytics.raw_load.shopify_order_line_items_api_latest` AS line_items
    LEFT JOIN `mischief-made-analytics.raw_load.shopify_orders_api_latest` AS orders
      ON line_items.shopify_order_graphql_id = orders.shopify_order_graphql_id
  ),

  api_line_items_by_order AS (
    SELECT
      api_order_number,
      COUNT(*) AS api_line_item_count,
      SUM(api_quantity) AS api_total_items,
      COUNT(DISTINCT api_normalized_sku) AS api_distinct_sku_count,
      SUM(api_discounted_total) AS api_line_items_discounted_total,
      SUM(api_total_discount) AS api_line_items_total_discount
    FROM api_line_items
    GROUP BY api_order_number
  ),

  api_orders_with_items AS (
    SELECT
      orders.*,
      line_items.api_line_item_count,
      line_items.api_total_items,
      line_items.api_distinct_sku_count,
      line_items.api_line_items_discounted_total,
      line_items.api_line_items_total_discount
    FROM api_orders AS orders
    LEFT JOIN api_line_items_by_order AS line_items
      ON orders.api_order_number = line_items.api_order_number
  ),

  staging_orders_recent AS (
    SELECT
      staging.shopify_order_id AS staging_shopify_order_id,
      staging.order_number AS staging_order_number,
      LOWER(TRIM(staging.customer_email)) AS staging_normalized_customer_email,
      staging.customer_email AS staging_customer_email,
      staging.created_at_ts AS staging_created_at_ts,
      staging.paid_at_ts AS staging_paid_at_ts,
      staging.fulfilled_at_ts AS staging_fulfilled_at_ts,
      staging.cancelled_at_ts AS staging_cancelled_at_ts,
      LOWER(TRIM(staging.financial_status)) AS staging_financial_status_normalized,
      staging.financial_status AS staging_financial_status,
      LOWER(TRIM(staging.fulfillment_status)) AS staging_fulfillment_status_normalized,
      staging.fulfillment_status AS staging_fulfillment_status,
      staging.currency AS staging_currency,
      staging.order_source AS staging_order_source,
      staging.risk_level AS staging_risk_level,
      staging.order_subtotal AS staging_order_subtotal,
      staging.order_shipping AS staging_order_shipping,
      staging.order_taxes AS staging_order_taxes,
      staging.order_total AS staging_order_total,
      staging.order_discount_amount AS staging_order_discount_amount,
      staging.refunded_amount AS staging_refunded_amount,
      staging.total_items AS staging_total_items,
      staging.line_item_count AS staging_line_item_count,
      staging.distinct_sku_count AS staging_distinct_sku_count,
      staging.billing_city AS staging_billing_city,
      staging.billing_province AS staging_billing_province,
      staging.billing_country AS staging_billing_country,
      staging.shipping_city AS staging_shipping_city,
      staging.shipping_province AS staging_shipping_province,
      staging.shipping_country AS staging_shipping_country,
      staging.payment_method AS staging_payment_method,
      staging.shipping_method AS staging_shipping_method,
      staging.tags AS staging_tags
    FROM `mischief-made-analytics.staging.stg_shopify_orders` AS staging
    CROSS JOIN api_window
    WHERE DATE(staging.created_at_ts)
      BETWEEN DATE(api_window.api_min_created_at_ts)
      AND DATE(api_window.api_max_created_at_ts)
  ),

  staging_order_items_recent AS (
    SELECT
      items.order_number AS staging_order_number,
      COUNT(*) AS staging_item_rows_from_items,
      SUM(items.quantity) AS staging_total_items_from_items,
      COUNT(DISTINCT NULLIF(LOWER(TRIM(items.sku)), '')) AS staging_distinct_sku_count_from_items,
      SUM(items.lineitem_price * items.quantity) AS staging_gross_item_revenue_from_items,
      SUM(items.lineitem_discount) AS staging_lineitem_discount_from_items
    FROM `mischief-made-analytics.staging.stg_shopify_order_items` AS items
    CROSS JOIN api_window
    WHERE DATE(items.created_at_ts)
      BETWEEN DATE(api_window.api_min_created_at_ts)
      AND DATE(api_window.api_max_created_at_ts)
    GROUP BY items.order_number
  ),

  fct_orders_recent AS (
    SELECT
      fct.shopify_order_id AS fct_shopify_order_id,
      fct.order_number AS fct_order_number,
      LOWER(TRIM(fct.customer_email)) AS fct_normalized_customer_email,
      fct.customer_email AS fct_customer_email,
      fct.created_at_ts AS fct_created_at_ts,
      fct.paid_at_ts AS fct_paid_at_ts,
      fct.fulfilled_at_ts AS fct_fulfilled_at_ts,
      fct.cancelled_at_ts AS fct_cancelled_at_ts,
      LOWER(TRIM(fct.financial_status)) AS fct_financial_status_normalized,
      fct.financial_status AS fct_financial_status,
      LOWER(TRIM(fct.fulfillment_status)) AS fct_fulfillment_status_normalized,
      fct.fulfillment_status AS fct_fulfillment_status,
      fct.currency AS fct_currency,
      fct.order_source AS fct_order_source,
      fct.risk_level AS fct_risk_level,
      fct.order_subtotal AS fct_order_subtotal,
      fct.order_shipping AS fct_order_shipping,
      fct.order_taxes AS fct_order_taxes,
      fct.order_total AS fct_order_total,
      fct.order_discount_amount AS fct_order_discount_amount,
      fct.refunded_amount AS fct_refunded_amount,
      fct.total_items AS fct_total_items,
      fct.line_item_count AS fct_line_item_count,
      fct.distinct_sku_count AS fct_distinct_sku_count,
      fct.billing_city AS fct_billing_city,
      fct.billing_province AS fct_billing_province,
      fct.billing_country AS fct_billing_country,
      fct.shipping_city AS fct_shipping_city,
      fct.shipping_province AS fct_shipping_province,
      fct.shipping_country AS fct_shipping_country,
      fct.payment_method AS fct_payment_method,
      fct.shipping_method AS fct_shipping_method,
      fct.tags AS fct_tags
    FROM `mischief-made-analytics.marts.fct_orders` AS fct
    CROSS JOIN api_window
    WHERE DATE(fct.created_at_ts)
      BETWEEN DATE(api_window.api_min_created_at_ts)
      AND DATE(api_window.api_max_created_at_ts)
  )

SELECT
  COALESCE(api.api_order_number, staging.staging_order_number) AS unified_order_number,
  COALESCE(api.api_shopify_order_id, staging.staging_shopify_order_id) AS unified_shopify_order_id,

  api_window.api_min_created_at_ts,
  api_window.api_max_created_at_ts,

  api.shopify_order_graphql_id,
  api.api_shopify_order_id,
  staging.staging_shopify_order_id,
  fct.fct_shopify_order_id,

  api.api_order_number,
  staging.staging_order_number,
  fct.fct_order_number,

  api.api_created_at_ts,
  staging.staging_created_at_ts,
  fct.fct_created_at_ts,

  api.api_processed_at_ts,
  staging.staging_paid_at_ts,
  fct.fct_paid_at_ts,

  api.api_cancelled_at_ts,
  staging.staging_cancelled_at_ts,
  fct.fct_cancelled_at_ts,

  api.api_customer_email,
  staging.staging_customer_email,
  fct.fct_customer_email,

  api.api_customer_legacy_resource_id,
  api.api_customer_graphql_id,

  api.api_financial_status,
  staging.staging_financial_status,
  fct.fct_financial_status,

  api.api_fulfillment_status,
  staging.staging_fulfillment_status,
  fct.fct_fulfillment_status,

  api.api_currency,
  staging.staging_currency,
  fct.fct_currency,

  api.api_order_source,
  staging.staging_order_source,
  fct.fct_order_source,

  staging.staging_risk_level,
  fct.fct_risk_level,

  api.api_order_subtotal,
  staging.staging_order_subtotal,
  fct.fct_order_subtotal,

  api.api_order_shipping,
  staging.staging_order_shipping,
  fct.fct_order_shipping,

  api.api_order_taxes,
  staging.staging_order_taxes,
  fct.fct_order_taxes,

  api.api_order_total,
  staging.staging_order_total,
  fct.fct_order_total,

  api.api_order_discount_amount,
  staging.staging_order_discount_amount,
  fct.fct_order_discount_amount,

  api.api_refunded_amount,
  staging.staging_refunded_amount,
  fct.fct_refunded_amount,

  api.api_line_item_count,
  staging.staging_line_item_count,
  staging_items.staging_item_rows_from_items,
  fct.fct_line_item_count,

  api.api_total_items,
  staging.staging_total_items,
  staging_items.staging_total_items_from_items,
  fct.fct_total_items,

  api.api_distinct_sku_count,
  staging.staging_distinct_sku_count,
  staging_items.staging_distinct_sku_count_from_items,
  fct.fct_distinct_sku_count,

  api.api_line_items_discounted_total,
  staging_items.staging_gross_item_revenue_from_items,
  staging_items.staging_lineitem_discount_from_items,

  api.api_billing_city,
  staging.staging_billing_city,
  fct.fct_billing_city,

  api.api_billing_province,
  staging.staging_billing_province,
  fct.fct_billing_province,

  api.api_billing_country,
  staging.staging_billing_country,
  fct.fct_billing_country,

  api.api_shipping_city,
  staging.staging_shipping_city,
  fct.fct_shipping_city,

  api.api_shipping_province,
  staging.staging_shipping_province,
  fct.fct_shipping_province,

  api.api_shipping_country,
  staging.staging_shipping_country,
  fct.fct_shipping_country,

  api.api_payment_gateway_names_json,
  staging.staging_payment_method,
  fct.fct_payment_method,

  api.api_shipping_method,
  staging.staging_shipping_method,
  fct.fct_shipping_method,

  api.api_tags_json,
  staging.staging_tags,
  fct.fct_tags,

  ROUND(api.api_order_total - staging.staging_order_total, 2)
    AS api_vs_staging_order_total_diff,

  ROUND(api.api_order_subtotal - staging.staging_order_subtotal, 2)
    AS api_vs_staging_order_subtotal_diff,

  ROUND(api.api_order_shipping - staging.staging_order_shipping, 2)
    AS api_vs_staging_order_shipping_diff,

  ROUND(api.api_order_taxes - staging.staging_order_taxes, 2)
    AS api_vs_staging_order_taxes_diff,

  ROUND(api.api_order_discount_amount - staging.staging_order_discount_amount, 2)
    AS api_vs_staging_order_discount_amount_diff,

  ROUND(api.api_refunded_amount - staging.staging_refunded_amount, 2)
    AS api_vs_staging_refunded_amount_diff,

  api.api_line_item_count - staging.staging_line_item_count
    AS api_vs_staging_line_item_count_diff,

  api.api_total_items - staging.staging_total_items
    AS api_vs_staging_total_items_diff,

  api.api_distinct_sku_count - staging.staging_distinct_sku_count
    AS api_vs_staging_distinct_sku_count_diff,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_in_api_window'
    WHEN staging.staging_order_number IS NULL THEN 'api_only'
    WHEN fct.fct_order_number IS NOT NULL THEN 'matched_api_staging_fct'
    ELSE 'matched_api_staging_missing_fct'
  END AS reconciliation_status,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_no_api_total_compare'
    WHEN staging.staging_order_number IS NULL THEN 'api_only_no_staging_total_compare'
    WHEN api.api_order_total IS NULL THEN 'missing_api_order_total'
    WHEN staging.staging_order_total IS NULL THEN 'missing_staging_order_total'
    WHEN ROUND(api.api_order_total - staging.staging_order_total, 2) = 0
      THEN 'order_total_matches_staging'
    ELSE 'order_total_differs_from_staging'
  END AS order_total_reconciliation_status,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_no_api_item_count_compare'
    WHEN staging.staging_order_number IS NULL THEN 'api_only_no_staging_item_count_compare'
    WHEN api.api_line_item_count IS NULL THEN 'missing_api_line_item_count'
    WHEN staging.staging_line_item_count IS NULL THEN 'missing_staging_line_item_count'
    WHEN api.api_line_item_count = staging.staging_line_item_count
      THEN 'line_item_count_matches_staging'
    ELSE 'line_item_count_differs_from_staging'
  END AS line_item_count_reconciliation_status,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_no_api_total_items_compare'
    WHEN staging.staging_order_number IS NULL THEN 'api_only_no_staging_total_items_compare'
    WHEN api.api_total_items IS NULL THEN 'missing_api_total_items'
    WHEN staging.staging_total_items IS NULL THEN 'missing_staging_total_items'
    WHEN api.api_total_items = staging.staging_total_items
      THEN 'total_items_matches_staging'
    ELSE 'total_items_differs_from_staging'
  END AS total_items_reconciliation_status,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_no_api_status_compare'
    WHEN staging.staging_order_number IS NULL THEN 'api_only_no_staging_status_compare'
    WHEN api.api_financial_status_normalized = staging.staging_financial_status_normalized
      THEN 'financial_status_matches_staging'
    ELSE 'financial_status_differs_from_staging'
  END AS financial_status_reconciliation_status,

  CASE
    WHEN api.api_order_number IS NULL THEN 'staging_only_no_api_fulfillment_compare'
    WHEN staging.staging_order_number IS NULL THEN 'api_only_no_staging_fulfillment_compare'
    WHEN api.api_fulfillment_status_normalized = staging.staging_fulfillment_status_normalized
      THEN 'fulfillment_status_matches_staging'
    ELSE 'fulfillment_status_differs_from_staging'
  END AS fulfillment_status_reconciliation_status

FROM api_orders_with_items AS api
FULL OUTER JOIN staging_orders_recent AS staging
  ON api.api_order_number = staging.staging_order_number
LEFT JOIN fct_orders_recent AS fct
  ON COALESCE(api.api_order_number, staging.staging_order_number) = fct.fct_order_number
LEFT JOIN staging_order_items_recent AS staging_items
  ON COALESCE(api.api_order_number, staging.staging_order_number) = staging_items.staging_order_number
CROSS JOIN api_window;