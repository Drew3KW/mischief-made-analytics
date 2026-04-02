-- sql/analysis/product_family_customer_mix_review.sql
-- Purpose:
-- Business-facing review queries for product-family customer mix analysis.

-- 1) Families with the most unique customers
SELECT
    product_family_name,
    customers_who_bought_family,
    orders_containing_family,
    units_sold,
    gross_family_revenue,
    pct_repeat_customers,
    customers_first_buying_this_family
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
ORDER BY customers_who_bought_family DESC
LIMIT 50;


-- 2) Families with the highest repeat-customer share
SELECT
    product_family_name,
    customers_who_bought_family,
    repeat_customers_who_bought_family,
    one_time_customers_who_bought_family,
    pct_repeat_customers,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE customers_who_bought_family >= 10
ORDER BY pct_repeat_customers DESC, customers_who_bought_family DESC
LIMIT 50;


-- 3) Families most often appearing in customers' first orders
SELECT
    product_family_name,
    customers_first_buying_this_family,
    customers_who_bought_family,
    pct_of_family_customers_first_buying_this_family,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
ORDER BY customers_first_buying_this_family DESC
LIMIT 50;


-- 4) Families associated with higher-value customers
SELECT
    product_family_name,
    customers_who_bought_family,
    avg_customer_lifetime_revenue,
    avg_customer_lifetime_orders,
    pct_repeat_customers,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE customers_who_bought_family >= 10
ORDER BY avg_customer_lifetime_revenue DESC
LIMIT 50;


-- 5) Families that look more acquisition-oriented
SELECT
    product_family_name,
    customers_who_bought_family,
    customers_first_buying_this_family,
    pct_of_family_customers_first_buying_this_family,
    pct_repeat_customers,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE customers_who_bought_family >= 10
ORDER BY pct_of_family_customers_first_buying_this_family DESC, customers_who_bought_family DESC
LIMIT 50;


-- 6) Families that look more loyalty-oriented
SELECT
    product_family_name,
    customers_who_bought_family,
    pct_repeat_customers,
    avg_customer_lifetime_revenue,
    avg_customer_lifetime_orders,
    gross_family_revenue
FROM `mischief-made-analytics.marts.anl_product_family_customer_mix`
WHERE customers_who_bought_family >= 10
ORDER BY pct_repeat_customers DESC, avg_customer_lifetime_revenue DESC
LIMIT 50;
