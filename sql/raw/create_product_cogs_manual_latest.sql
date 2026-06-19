-- sql/raw/create_product_cogs_manual_latest.sql
-- Purpose:
-- Create the manual product COGS latest table.
--
-- Notes:
-- - This table is loaded from a local private CSV export.
-- - The source CSV is not committed to GitHub.
-- - The source spreadsheet has duplicate blank column headers, so the loader
--   reads columns by position and writes normalized field names.
-- - Raw string fields are preserved alongside parsed numeric fields.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.product_cogs_manual_latest` (
    source_file_name STRING,
    source_row_number INT64,
    loaded_at TIMESTAMP,

    raw_notes_1 STRING,
    sku STRING,
    family_name STRING,
    price_raw STRING,
    profit_raw STRING,
    faire_15_fee_amount_raw STRING,
    faire_profit_raw STRING,
    raw_notes_2 STRING,
    cost_raw STRING,
    raw_notes_3 STRING,

    normalized_sku STRING,
    normalized_family_name STRING,

    reference_price NUMERIC,
    reference_profit NUMERIC,
    reference_faire_15_fee_amount NUMERIC,
    reference_faire_profit NUMERIC,
    unit_cogs NUMERIC,

    has_sku BOOL,
    has_family_name BOOL,
    has_unit_cogs BOOL
);