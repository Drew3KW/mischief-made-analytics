-- File: sql/raw/rebuild_shopify_orders.sql
-- Model: raw.shopify_orders
-- Purpose:
--   Rebuild the canonical raw Shopify orders table by combining:
--   1) existing canonical raw history
--   2) the latest landed import table
--   then deduplicating to preserve one preferred row per line-item fingerprint.
--
-- Grain:
--   One row per Shopify order line item in the raw export.
--
-- Important notes:
-- - raw.shopify_orders is NOT order-grain; multi-line-item orders can repeat Name.
-- - We therefore deduplicate at an approximate line-item business-identity level,
--   not on Name alone.
-- - When the same fingerprint appears in both existing and incoming data,
--   the incoming row wins.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_orders` AS
WITH combined AS (
  SELECT
    existing.*,
    0 AS source_rank
  FROM `mischief-made-analytics.raw.shopify_orders` AS existing

  UNION ALL

  SELECT
    incoming.*,
    1 AS source_rank
  FROM `mischief-made-analytics.raw_load.shopify_orders_latest` AS incoming
),

fingerprinted AS (
  SELECT
    * EXCEPT(source_rank),
    source_rank,
    TO_HEX(
      MD5(
        CONCAT(
          COALESCE(TRIM(`Name`), ''), '||',
          COALESCE(TRIM(`Lineitem sku`), ''), '||',
          COALESCE(TRIM(`Lineitem name`), ''), '||',
          COALESCE(TRIM(`Lineitem quantity`), ''), '||',
          COALESCE(TRIM(`Lineitem price`), ''), '||',
          COALESCE(TRIM(`Created at`), ''), '||',
          COALESCE(LOWER(TRIM(`Email`)), '')
        )
      )
    ) AS dedupe_fingerprint
  FROM combined
),

deduped AS (
  SELECT
    * EXCEPT(source_rank, dedupe_fingerprint)
  FROM fingerprinted
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_fingerprint
    ORDER BY source_rank DESC
  ) = 1
)

SELECT *
FROM deduped;