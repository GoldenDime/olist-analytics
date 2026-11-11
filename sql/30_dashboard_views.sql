-- 30_dashboard_views.sql — витрины (views) для дашборда в Metabase.
-- Логика расчётов живёт здесь, в SQL под контролем версий; Metabase только рисует.
-- Требует view first_orders из sql/20_delivery_reviews.sql.
SET search_path TO olist;

-- Валидные заказы с GMV и человеком
CREATE OR REPLACE VIEW v_valid_orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp,
       date_trunc('month', o.order_purchase_timestamp)::date AS month,
       i.gmv,
       i.freight
FROM orders o
JOIN customers c USING (customer_id)
JOIN (SELECT order_id, sum(price) AS gmv, sum(freight_value) AS freight
      FROM order_items GROUP BY order_id) i USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable');

-- Помесячные метрики (полные месяцы)
CREATE OR REPLACE VIEW v_monthly AS
SELECT month,
       count(*)                           AS orders,
       count(DISTINCT customer_unique_id) AS buyers,
       round(sum(gmv))                    AS gmv,
       round(avg(gmv), 2)                 AS aov
FROM v_valid_orders
WHERE month BETWEEN '2017-01-01' AND '2018-08-01'
GROUP BY month;

-- Когортная таблица: доля вернувшихся в месяц N (длинный формат для pivot)
CREATE OR REPLACE VIEW v_cohort_retention AS
WITH f AS (
    SELECT customer_unique_id, min(month) AS cohort FROM v_valid_orders GROUP BY 1
), act AS (
    SELECT DISTINCT v.customer_unique_id, f.cohort,
           ((extract(year FROM v.month) - extract(year FROM f.cohort)) * 12
           + extract(month FROM v.month) - extract(month FROM f.cohort))::int AS month_n
    FROM v_valid_orders v JOIN f USING (customer_unique_id)
), sz AS (SELECT cohort, count(*) AS buyers FROM f GROUP BY 1)
SELECT a.cohort, a.month_n, s.buyers,
       round(100.0 * count(*) / s.buyers, 2) AS retention_pct
FROM act a JOIN sz s USING (cohort)
WHERE a.cohort BETWEEN '2017-01-01' AND '2018-07-01'
  AND a.month_n BETWEEN 1 AND 12
  AND a.cohort + (a.month_n || ' month')::interval <= '2018-08-01'
GROUP BY a.cohort, a.month_n, s.buyers;

-- Опоздание -> оценка и повтор
CREATE OR REPLACE VIEW v_delay_effect AS
SELECT CASE WHEN delay_days <= -10 THEN '1. на 10+ дн. раньше'
            WHEN delay_days <= 0   THEN '2. вовремя'
            WHEN delay_days <= 7   THEN '3. опоздание 1–7 дн.'
            ELSE                        '4. опоздание 8+ дн.' END AS delivery,
       count(*) AS first_orders,
       round(avg(review_score), 2) AS avg_review,
       round(100.0 * avg((review_score <= 2)::int), 1) AS bad_review_pct,
       round(100.0 * avg(repeat_180d::int), 2) AS repeat_180d_pct
FROM first_orders GROUP BY 1;

-- Срок доставки -> повтор
CREATE OR REPLACE VIEW v_delivery_time_effect AS
SELECT CASE WHEN delivery_days < 7  THEN '1. до 7 дн.'
            WHEN delivery_days < 14 THEN '2. 7–13 дн.'
            WHEN delivery_days < 21 THEN '3. 14–20 дн.'
            ELSE                         '4. 21+ дн.' END AS delivery_time,
       count(*) AS first_orders,
       round(avg(review_score), 2) AS avg_review,
       round(100.0 * avg(repeat_180d::int), 2) AS repeat_180d_pct
FROM first_orders GROUP BY 1;

-- Топ категорий по GMV
CREATE OR REPLACE VIEW v_categories AS
SELECT coalesce(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       count(DISTINCT i.order_id) AS orders,
       round(sum(i.price)) AS gmv
FROM order_items i
JOIN orders o USING (order_id)
JOIN products p USING (product_id)
LEFT JOIN category_translation t USING (product_category_name)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
  AND o.order_purchase_timestamp >= '2017-01-01' AND o.order_purchase_timestamp < '2018-09-01'
GROUP BY 1;

-- KPI-плитки
CREATE OR REPLACE VIEW v_kpi AS
SELECT (SELECT sum(orders) FROM v_monthly)           AS orders,
       (SELECT sum(gmv) FROM v_monthly)              AS gmv,
       (SELECT round(sum(gmv) / sum(orders), 2) FROM v_monthly) AS aov,
       (SELECT round(100.0 * avg(repeat_180d::int), 2) FROM first_orders) AS repeat_180d_pct;

GRANT SELECT ON ALL TABLES IN SCHEMA olist TO PUBLIC;

-- Та же когортная таблица в широком формате (строка = когорта, столбцы = месяцы 1–6) для Metabase
CREATE OR REPLACE VIEW v_cohort_wide AS
SELECT to_char(cohort, 'YYYY-MM') AS cohort,
       max(buyers) AS buyers,
       max(retention_pct) FILTER (WHERE month_n = 1) AS m1,
       max(retention_pct) FILTER (WHERE month_n = 2) AS m2,
       max(retention_pct) FILTER (WHERE month_n = 3) AS m3,
       max(retention_pct) FILTER (WHERE month_n = 4) AS m4,
       max(retention_pct) FILTER (WHERE month_n = 5) AS m5,
       max(retention_pct) FILTER (WHERE month_n = 6) AS m6
FROM v_cohort_retention
GROUP BY cohort;
GRANT SELECT ON v_cohort_wide TO PUBLIC;
