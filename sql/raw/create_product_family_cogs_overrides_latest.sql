-- sql/raw/create_product_family_cogs_overrides_latest.sql
-- Purpose:
-- Create the manual product-family COGS override latest table.
--
-- Notes:
-- - This table is loaded from a local private CSV.
-- - The CSV is not committed to GitHub.
-- - Overrides are explicit manual decisions used to improve COGS coverage.
-- - Rows can either estimate COGS or exclude non-product/bundle rows from
--   product profitability modeling.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.product_family_cogs_overrides_latest` (
    source_file_name STRING,
    source_row_number INT64,
    loaded_at TIMESTAMP,

    product_family_key STRING,
    product_family_name STRING,
    unit_cogs_raw STRING,
    override_action STRING,
    override_reason STRING,
    notes STRING,

    normalized_product_family_key STRING,
    unit_cogs NUMERIC,

    is_estimate_cogs BOOL,
    is_exclude_from_profit_model BOOL,
    has_unit_cogs BOOL
);