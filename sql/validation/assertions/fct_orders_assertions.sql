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


