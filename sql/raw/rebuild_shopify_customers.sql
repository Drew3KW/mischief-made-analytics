-- File: sql/raw/rebuild_shopify_customers.sql
-- Model: raw.shopify_customers
-- Purpose:
--   Rebuild the canonical raw Shopify customers table by combining:
--   1) existing canonical raw history
--   2) the latest landed import table
--   then deduplicating to preserve one preferred row per customer key.
--
-- Grain:
--   One row per customer export row.
--
-- Important notes:
-- - Prefer customer_id as the raw dedupe key when present.
-- - Fall back to normalized email when customer_id is missing.
-- - If both are missing, fall back to a lightweight row fingerprint so we
--   can still collapse obvious exact/near-exact duplicates.
-- - When the same dedupe key appears in both existing and incoming data,
--   the incoming row wins.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_customers` AS
WITH combined AS (
  SELECT
    existing.*,
    0 AS source_rank
  FROM `mischief-made-analytics.raw.shopify_customers` AS existing

  UNION ALL

  SELECT
    incoming.*,
    1 AS source_rank
  FROM `mischief-made-analytics.raw_load.shopify_customers_latest` AS incoming
),

keyed AS (
  SELECT
    * EXCEPT(source_rank),
    source_rank,
    CASE
      WHEN NULLIF(TRIM(customer_id), '') IS NOT NULL THEN
        CONCAT('customer_id::', TRIM(customer_id))

      WHEN NULLIF(LOWER(TRIM(email)), '') IS NOT NULL THEN
        CONCAT('email::', LOWER(TRIM(email)))

      ELSE
        CONCAT(
          'fingerprint::',
          TO_HEX(
            MD5(
              TO_JSON_STRING(
                STRUCT(
                  customer_id,
                  email,
                  first_name,
                  last_name,
                  phone,
                  default_address_address1,
                  default_address_zip
                )
              )
            )
          )
        )
    END AS dedupe_key
  FROM combined
),

deduped AS (
  SELECT
    * EXCEPT(source_rank, dedupe_key)
  FROM keyed
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_key
    ORDER BY source_rank DESC
  ) = 1
)

SELECT *
FROM deduped;