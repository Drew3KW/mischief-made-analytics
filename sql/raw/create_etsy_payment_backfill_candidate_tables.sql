-- sql/raw/create_etsy_payment_backfill_candidate_tables.sql
-- Purpose:
-- Create shared candidate tables for Etsy historical payment enrichment.
--
-- Notes:
-- - Successful payment rows append into one shared candidate table.
-- - The candidate payment table mirrors the existing latest payment schema.
-- - Skipped receipt IDs are tracked separately for validation/debugging.
-- - Do not drop or replace these tables during normal backfill runs.

CREATE TABLE IF NOT EXISTS `mischief-made-analytics.raw_load.etsy_receipt_payments_api_payment_backfill_candidate`
LIKE `mischief-made-analytics.raw_load.etsy_receipt_payments_api_latest`;

CREATE TABLE IF NOT EXISTS `mischief-made-analytics.raw_load.etsy_receipt_payments_api_payment_backfill_skipped_receipts` (
    receipt_id INT64,
    batch_id STRING,
    skip_reason STRING,
    http_status INT64,
    error_message STRING,
    skipped_at TIMESTAMP
);