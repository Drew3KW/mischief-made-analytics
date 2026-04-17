-- sql/validation/assertions/product_family_models_assertions.sql

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT product_key
      FROM `mischief-made-analytics.marts.product_family_map`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'product_family_map has duplicate product_key values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      SELECT product_family_key
      FROM `mischief-made-analytics.marts.dim_product_families`
      GROUP BY 1
      HAVING COUNT(*) > 1
    )
  ) = 0
) AS 'dim_product_families has duplicate product_family_key values';

ASSERT (
  (
    SELECT COUNT(*)
    FROM `mischief-made-analytics.marts.dim_product_families` dpf
    LEFT JOIN `mischief-made-analytics.marts.product_family_map` pfm
      ON dpf.product_family_key = pfm.product_family_key
    WHERE pfm.product_family_key IS NULL
  ) = 0
) AS 'dim_product_families contains family keys not present in product_family_map';

ASSERT (
  (
    SELECT COUNT(*)
    FROM (
      WITH map_counts AS (
        SELECT COUNT(*) AS map_rows
        FROM `mischief-made-analytics.marts.product_family_map`
      ),
      hist_counts AS (
        SELECT COUNT(*) AS hist_rows
        FROM `mischief-made-analytics.marts.dim_products_historical`
      )
      SELECT 1
      FROM map_counts
      CROSS JOIN hist_counts
      WHERE map_rows != hist_rows
    )
  ) = 0
) AS 'product_family_map row count does not match dim_products_historical';
