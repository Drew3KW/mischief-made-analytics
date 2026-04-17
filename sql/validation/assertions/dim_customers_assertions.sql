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
    FROM `mischief-made-analytics.marts.dim_customers`
    WHERE customer_email IS NULL
       OR TRIM(customer_email) = ''
  ) = 0
) AS 'dim_customers has null or blank customer_email values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT DISTINCT LOWER(TRIM(customer_email)) AS customer_email
      FROM `mischief-made-analytics.staging.stg_shopify_customers`
      WHERE customer_email IS NOT NULL
        AND TRIM(customer_email) <> ''
    ) s
    LEFT JOIN `mischief-made-analytics.marts.dim_customers` d
      ON s.customer_email = d.customer_email
    WHERE d.customer_email IS NULL
  ) = 0
) AS 'dim_customers is missing nonblank staged customer export emails';
