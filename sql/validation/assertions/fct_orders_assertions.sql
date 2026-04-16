-- sql/validation/assertions/fct_orders_assertions.sql

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.staging.stg_shopify_orders`
  ) = (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.fct_orders`
  )
) AS 'fct_orders row count does not match stg_shopify_orders';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT order_number
      FROM `mischief-made-analytics.marts.fct_orders`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'fct_orders has duplicate order_number values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.fct_orders` f
    LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
      ON f.customer_email = c.customer_email
    WHERE f.customer_email IS NOT NULL
      AND TRIM(f.customer_email) <> ''
      AND c.customer_email IS NULL
  ) = 0
) AS 'fct_orders has non-null customer_email values not found in dim_customers';
