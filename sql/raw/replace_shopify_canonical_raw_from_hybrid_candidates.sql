-- File: sql/raw/replace_shopify_canonical_raw_from_hybrid_candidates.sql
-- Purpose:
-- Replace production Shopify canonical raw tables using validated hybrid raw
-- candidate tables.
--
-- Important notes:
-- - Run the backup script before this script.
-- - Run the latest hybrid raw candidate scripts before this script.
-- - This is the first manual production canonical raw replacement MVP.
-- - This does not modify staging SQL, marts SQL, analysis SQL, or DAG behavior.
-- - Hybrid metadata columns are excluded so canonical raw schemas remain clean.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_products` AS
SELECT * EXCEPT(_hybrid_source)
FROM `mischief-made-analytics.raw_load.shopify_products_hybrid_raw_candidate`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_customers` AS
SELECT * EXCEPT(_hybrid_source)
FROM `mischief-made-analytics.raw_load.shopify_customers_hybrid_raw_candidate`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_orders` AS
SELECT * EXCEPT(_hybrid_source, _api_cutover_date)
FROM `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate`;