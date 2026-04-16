-- sql/validation/assertions/dim_customers_assertions.sql

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT customer_email
      FROM `mischief-made-analytics.marts.dim_customers`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'dim_customers has duplicate customer_email values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.staging.stg_shopify_orders` o
    LEFT JOIN `mischief-made-analytics.marts.dim_customers` c
      ON LOWER(TRIM(o.customer_email)) = c.customer_email
    WHERE o.customer_email IS NOT NULL
      AND TRIM(o.customer_email) <> ''
      AND c.customer_email IS NULL
  ) = 0
) AS 'dim_customers is missing non-null staged customer emails';
