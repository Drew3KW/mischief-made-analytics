-- File: sql/raw/create_shopify_orders_hybrid_raw_candidate.sql
-- Model: raw_load.shopify_orders_hybrid_raw_candidate
-- Purpose:
-- Create a non-production hybrid raw orders candidate by combining:
-- 1) CSV-derived canonical raw order history before a derived API cutover date
-- 2) API-derived raw order candidates on or after that cutover date
--
-- Important notes:
-- - This does not modify raw.shopify_orders.
-- - This does not modify staging, marts, analysis, or DAG behavior.
-- - Output grain remains one row per order line item.
-- - The derived API cutover date is the day after the latest parseable
--   Created at date in current raw.shopify_orders.
-- - This conservative cutover avoids rewriting existing CSV-derived history.
-- - This table is for validation before any future canonical raw replacement.

CREATE OR REPLACE TABLE `mischief-made-analytics.raw_load.shopify_orders_hybrid_raw_candidate` AS

WITH cutover AS (
  SELECT
    DATE_ADD(
      MAX(DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`))),
      INTERVAL 1 DAY
    ) AS api_cutover_date
  FROM `mischief-made-analytics.raw.shopify_orders`
  WHERE SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`) IS NOT NULL
),

csv_history AS (
  SELECT
    CAST(`Id` AS STRING) AS `Id`,
    CAST(`Name` AS STRING) AS `Name`,
    CAST(`Lineitem sku` AS STRING) AS `Lineitem sku`,
    CAST(`Lineitem name` AS STRING) AS `Lineitem name`,
    CAST(`Email` AS STRING) AS `Email`,
    CAST(`Created at` AS STRING) AS `Created at`,
    CAST(`Paid at` AS STRING) AS `Paid at`,
    CAST(`Fulfilled at` AS STRING) AS `Fulfilled at`,
    CAST(`Cancelled at` AS STRING) AS `Cancelled at`,
    CAST(`Financial Status` AS STRING) AS `Financial Status`,
    CAST(`Fulfillment Status` AS STRING) AS `Fulfillment Status`,
    CAST(`Lineitem fulfillment status` AS STRING) AS `Lineitem fulfillment status`,
    CAST(`Currency` AS STRING) AS `Currency`,
    CAST(`Source` AS STRING) AS `Source`,
    CAST(`Risk Level` AS STRING) AS `Risk Level`,
    CAST(`Lineitem quantity` AS STRING) AS `Lineitem quantity`,
    CAST(`Lineitem price` AS STRING) AS `Lineitem price`,
    CAST(`Lineitem compare at price` AS STRING) AS `Lineitem compare at price`,
    CAST(`Lineitem discount` AS STRING) AS `Lineitem discount`,
    CAST(`Subtotal` AS STRING) AS `Subtotal`,
    CAST(`Shipping` AS STRING) AS `Shipping`,
    CAST(`Taxes` AS STRING) AS `Taxes`,
    CAST(`Total` AS STRING) AS `Total`,
    CAST(`Discount Amount` AS STRING) AS `Discount Amount`,
    CAST(`Refunded Amount` AS STRING) AS `Refunded Amount`,
    CAST(`Vendor` AS STRING) AS `Vendor`,
    CAST(`Billing City` AS STRING) AS `Billing City`,
    CAST(`Billing Province` AS STRING) AS `Billing Province`,
    CAST(`Billing Country` AS STRING) AS `Billing Country`,
    CAST(`Shipping City` AS STRING) AS `Shipping City`,
    CAST(`Shipping Province` AS STRING) AS `Shipping Province`,
    CAST(`Shipping Country` AS STRING) AS `Shipping Country`,
    CAST(`Payment Method` AS STRING) AS `Payment Method`,
    CAST(`Shipping Method` AS STRING) AS `Shipping Method`,
    CAST(`Tags` AS STRING) AS `Tags`,

    -- Legacy CSV export columns preserved for canonical raw schema compatibility.
    CAST(`Accepts Marketing` AS STRING) AS `Accepts Marketing`,
    CAST(`Billing Address1` AS STRING) AS `Billing Address1`,
    CAST(`Billing Address2` AS STRING) AS `Billing Address2`,
    CAST(`Billing Company` AS STRING) AS `Billing Company`,
    CAST(`Billing Name` AS STRING) AS `Billing Name`,
    CAST(`Billing Phone` AS STRING) AS `Billing Phone`,
    CAST(`Billing Province Name` AS STRING) AS `Billing Province Name`,
    CAST(`Billing Street` AS STRING) AS `Billing Street`,
    CAST(`Billing Zip` AS STRING) AS `Billing Zip`,
    CAST(`Device ID` AS STRING) AS `Device ID`,
    CAST(`Discount Code` AS STRING) AS `Discount Code`,
    CAST(`Duties` AS STRING) AS `Duties`,
    CAST(`Employee` AS STRING) AS `Employee`,
    CAST(`Lineitem requires shipping` AS STRING) AS `Lineitem requires shipping`,
    CAST(`Lineitem taxable` AS STRING) AS `Lineitem taxable`,
    CAST(`Location` AS STRING) AS `Location`,
    CAST(`Next Payment Due At` AS STRING) AS `Next Payment Due At`,
    CAST(`Note Attributes` AS STRING) AS `Note Attributes`,
    CAST(`Notes` AS STRING) AS `Notes`,
    CAST(`Outstanding Balance` AS STRING) AS `Outstanding Balance`,
    CAST(`Payment ID` AS STRING) AS `Payment ID`,
    CAST(`Payment Reference` AS STRING) AS `Payment Reference`,
    CAST(`Payment References` AS STRING) AS `Payment References`,
    CAST(`Payment Terms Name` AS STRING) AS `Payment Terms Name`,
    CAST(`Phone` AS STRING) AS `Phone`,
    CAST(`Receipt Number` AS STRING) AS `Receipt Number`,
    CAST(`Shipping Address1` AS STRING) AS `Shipping Address1`,
    CAST(`Shipping Address2` AS STRING) AS `Shipping Address2`,
    CAST(`Shipping Company` AS STRING) AS `Shipping Company`,
    CAST(`Shipping Name` AS STRING) AS `Shipping Name`,
    CAST(`Shipping Phone` AS STRING) AS `Shipping Phone`,
    CAST(`Shipping Province Name` AS STRING) AS `Shipping Province Name`,
    CAST(`Shipping Street` AS STRING) AS `Shipping Street`,
    CAST(`Shipping Zip` AS STRING) AS `Shipping Zip`,
    CAST(`Tax 1 Name` AS STRING) AS `Tax 1 Name`,
    CAST(`Tax 1 Value` AS STRING) AS `Tax 1 Value`,
    CAST(`Tax 2 Name` AS STRING) AS `Tax 2 Name`,
    CAST(`Tax 2 Value` AS STRING) AS `Tax 2 Value`,
    CAST(`Tax 3 Name` AS STRING) AS `Tax 3 Name`,
    CAST(`Tax 3 Value` AS STRING) AS `Tax 3 Value`,
    CAST(`Tax 4 Name` AS STRING) AS `Tax 4 Name`,
    CAST(`Tax 4 Value` AS STRING) AS `Tax 4 Value`,
    CAST(`Tax 5 Name` AS STRING) AS `Tax 5 Name`,
    CAST(`Tax 5 Value` AS STRING) AS `Tax 5 Value`,

    'csv_history_before_cutover' AS _hybrid_source,
    cutover.api_cutover_date AS _api_cutover_date
  FROM `mischief-made-analytics.raw.shopify_orders`
  CROSS JOIN cutover
  WHERE DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`)) < cutover.api_cutover_date
),

api_forward AS (
  SELECT
    CAST(`Id` AS STRING) AS `Id`,
    CAST(`Name` AS STRING) AS `Name`,
    CAST(`Lineitem sku` AS STRING) AS `Lineitem sku`,
    CAST(`Lineitem name` AS STRING) AS `Lineitem name`,
    CAST(`Email` AS STRING) AS `Email`,
    CAST(`Created at` AS STRING) AS `Created at`,
    CAST(`Paid at` AS STRING) AS `Paid at`,
    CAST(`Fulfilled at` AS STRING) AS `Fulfilled at`,
    CAST(`Cancelled at` AS STRING) AS `Cancelled at`,
    CAST(`Financial Status` AS STRING) AS `Financial Status`,
    CAST(`Fulfillment Status` AS STRING) AS `Fulfillment Status`,
    CAST(`Lineitem fulfillment status` AS STRING) AS `Lineitem fulfillment status`,
    CAST(`Currency` AS STRING) AS `Currency`,
    CAST(`Source` AS STRING) AS `Source`,
    CAST(`Risk Level` AS STRING) AS `Risk Level`,
    CAST(`Lineitem quantity` AS STRING) AS `Lineitem quantity`,
    CAST(`Lineitem price` AS STRING) AS `Lineitem price`,
    CAST(`Lineitem compare at price` AS STRING) AS `Lineitem compare at price`,
    CAST(`Lineitem discount` AS STRING) AS `Lineitem discount`,
    CAST(`Subtotal` AS STRING) AS `Subtotal`,
    CAST(`Shipping` AS STRING) AS `Shipping`,
    CAST(`Taxes` AS STRING) AS `Taxes`,
    CAST(`Total` AS STRING) AS `Total`,
    CAST(`Discount Amount` AS STRING) AS `Discount Amount`,
    CAST(`Refunded Amount` AS STRING) AS `Refunded Amount`,
    CAST(`Vendor` AS STRING) AS `Vendor`,
    CAST(`Billing City` AS STRING) AS `Billing City`,
    CAST(`Billing Province` AS STRING) AS `Billing Province`,
    CAST(`Billing Country` AS STRING) AS `Billing Country`,
    CAST(`Shipping City` AS STRING) AS `Shipping City`,
    CAST(`Shipping Province` AS STRING) AS `Shipping Province`,
    CAST(`Shipping Country` AS STRING) AS `Shipping Country`,
    CAST(`Payment Method` AS STRING) AS `Payment Method`,
    CAST(`Shipping Method` AS STRING) AS `Shipping Method`,
    CAST(`Tags` AS STRING) AS `Tags`,

    -- Legacy CSV export columns preserved as NULL or API candidate values.
    CAST(`Accepts Marketing` AS STRING) AS `Accepts Marketing`,
    CAST(`Billing Address1` AS STRING) AS `Billing Address1`,
    CAST(`Billing Address2` AS STRING) AS `Billing Address2`,
    CAST(`Billing Company` AS STRING) AS `Billing Company`,
    CAST(`Billing Name` AS STRING) AS `Billing Name`,
    CAST(`Billing Phone` AS STRING) AS `Billing Phone`,
    CAST(`Billing Province Name` AS STRING) AS `Billing Province Name`,
    CAST(`Billing Street` AS STRING) AS `Billing Street`,
    CAST(`Billing Zip` AS STRING) AS `Billing Zip`,
    CAST(`Device ID` AS STRING) AS `Device ID`,
    CAST(`Discount Code` AS STRING) AS `Discount Code`,
    CAST(`Duties` AS STRING) AS `Duties`,
    CAST(`Employee` AS STRING) AS `Employee`,
    CAST(`Lineitem requires shipping` AS STRING) AS `Lineitem requires shipping`,
    CAST(`Lineitem taxable` AS STRING) AS `Lineitem taxable`,
    CAST(`Location` AS STRING) AS `Location`,
    CAST(`Next Payment Due At` AS STRING) AS `Next Payment Due At`,
    CAST(`Note Attributes` AS STRING) AS `Note Attributes`,
    CAST(`Notes` AS STRING) AS `Notes`,
    CAST(`Outstanding Balance` AS STRING) AS `Outstanding Balance`,
    CAST(`Payment ID` AS STRING) AS `Payment ID`,
    CAST(`Payment Reference` AS STRING) AS `Payment Reference`,
    CAST(`Payment References` AS STRING) AS `Payment References`,
    CAST(`Payment Terms Name` AS STRING) AS `Payment Terms Name`,
    CAST(`Phone` AS STRING) AS `Phone`,
    CAST(`Receipt Number` AS STRING) AS `Receipt Number`,
    CAST(`Shipping Address1` AS STRING) AS `Shipping Address1`,
    CAST(`Shipping Address2` AS STRING) AS `Shipping Address2`,
    CAST(`Shipping Company` AS STRING) AS `Shipping Company`,
    CAST(`Shipping Name` AS STRING) AS `Shipping Name`,
    CAST(`Shipping Phone` AS STRING) AS `Shipping Phone`,
    CAST(`Shipping Province Name` AS STRING) AS `Shipping Province Name`,
    CAST(`Shipping Street` AS STRING) AS `Shipping Street`,
    CAST(`Shipping Zip` AS STRING) AS `Shipping Zip`,
    CAST(`Tax 1 Name` AS STRING) AS `Tax 1 Name`,
    CAST(`Tax 1 Value` AS STRING) AS `Tax 1 Value`,
    CAST(`Tax 2 Name` AS STRING) AS `Tax 2 Name`,
    CAST(`Tax 2 Value` AS STRING) AS `Tax 2 Value`,
    CAST(`Tax 3 Name` AS STRING) AS `Tax 3 Name`,
    CAST(`Tax 3 Value` AS STRING) AS `Tax 3 Value`,
    CAST(`Tax 4 Name` AS STRING) AS `Tax 4 Name`,
    CAST(`Tax 4 Value` AS STRING) AS `Tax 4 Value`,
    CAST(`Tax 5 Name` AS STRING) AS `Tax 5 Name`,
    CAST(`Tax 5 Value` AS STRING) AS `Tax 5 Value`,

    'api_forward_on_or_after_cutover' AS _hybrid_source,
    cutover.api_cutover_date AS _api_cutover_date
  FROM `mischief-made-analytics.raw_load.shopify_orders_api_raw_candidate`
  CROSS JOIN cutover
  WHERE DATE(SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S %z', `Created at`)) >= cutover.api_cutover_date
),

combined AS (
  SELECT * FROM csv_history
  UNION ALL
  SELECT * FROM api_forward
),

fingerprinted AS (
  SELECT
    *,
    TO_HEX(
      MD5(
        CONCAT(
          COALESCE(TRIM(`Name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem sku`), ''),
          '||',
          COALESCE(TRIM(`Lineitem name`), ''),
          '||',
          COALESCE(TRIM(`Lineitem quantity`), ''),
          '||',
          COALESCE(TRIM(`Lineitem price`), ''),
          '||',
          COALESCE(TRIM(`Created at`), ''),
          '||',
          COALESCE(LOWER(TRIM(`Email`)), '')
        )
      )
    ) AS dedupe_fingerprint
  FROM combined
),

deduped AS (
  SELECT * EXCEPT(dedupe_fingerprint)
  FROM fingerprinted
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dedupe_fingerprint
    ORDER BY
      CASE _hybrid_source
        WHEN 'api_forward_on_or_after_cutover' THEN 1
        ELSE 0
      END DESC
  ) = 1
)

SELECT *
FROM deduped;