-- File: sql/raw/rollback_shopify_canonical_raw_from_pre_automated_refresh_backups.sql
-- Purpose:
-- Restore production Shopify canonical raw tables from the latest automated
-- refresh backups.
--
-- Important notes:
-- - Do not run this unless an automated canonical raw refresh needs rollback.
-- - After rollback, rerun mm_bigquery_refresh_mvp so downstream tables reflect
--   the restored canonical raw tables.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_products` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_products_pre_automated_refresh_backup_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_customers` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_customers_pre_automated_refresh_backup_latest`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw.shopify_orders` AS
SELECT *
FROM `mischief-made-analytics.raw_load.shopify_orders_pre_automated_refresh_backup_latest`;