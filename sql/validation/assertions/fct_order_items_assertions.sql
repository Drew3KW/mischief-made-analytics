-- sql/validation/assertions/fct_order_items_assertions.sql

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.staging.stg_shopify_order_items`
  ) = (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.fct_order_items`
  )
) AS 'fct_order_items row count does not match stg_shopify_order_items';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT order_item_key
      FROM `mischief-made-analytics.marts.fct_order_items`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'fct_order_items has duplicate order_item_key values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.fct_order_items` f
    LEFT JOIN `mischief-made-analytics.marts.dim_products_historical` p
      ON f.product_key = p.product_key
    WHERE p.product_key IS NULL
  ) = 0
) AS 'fct_order_items has product_key values missing from dim_products_historical';

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.fct_order_items` f
    LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
      ON f.customer_email = c.customer_email
    WHERE f.customer_email IS NOT NULL
      AND TRIM(f.customer_email) <> ''
      AND c.customer_email IS NULL
  ) = 0
) AS 'fct_order_items has non-null customer_email values not found in dim_customers';
