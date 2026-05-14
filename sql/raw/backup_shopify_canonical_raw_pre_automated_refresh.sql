-- File: sql/raw/backup_shopify_canonical_raw_pre_automated_refresh.sql
-- Purpose:
-- Create latest backup copies of current Shopify canonical raw tables before
-- the automated API-backed canonical raw refresh replaces them.
--
-- Important notes:
-- - This is intended for the automated refresh DAG.
-- - These backup tables are overwritten on each automated refresh attempt.
-- - They provide rollback to the immediately previous canonical raw state.
-- - Do not use these as historical archives.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_products_pre_automated_refresh_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_products`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_customers_pre_automated_refresh_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_customers`;

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_orders_pre_automated_refresh_backup_latest` AS
SELECT *
FROM `mischief-made-analytics.raw.shopify_orders`;