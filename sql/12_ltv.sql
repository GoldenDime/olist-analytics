-- 12_ltv.sql — LTV покупателя по GMV.
--
-- LTV(N) = средний GMV на одного человека за N дней с момента его первой покупки.
-- Считаем по GMV (стоимость товаров), а не по выручке Olist: комиссия маркетплейса
-- в датасете отсутствует, её мы введём как допущение в юнит-экономике.
-- Чтобы у всех было одинаковое «окно», берём только тех, у кого есть N дней истории:
--   180 дней — первая покупка 2017-01-01 … 2018-02-28
--   365 дней — первая покупка 2017-01-01 … 2017-08-31
SET search_path TO olist;

WITH purchases AS (
    SELECT c.customer_unique_id, o.order_id, o.order_purchase_timestamp AS ts
    FROM orders o JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
order_gmv AS (
    SELECT order_id, sum(price) AS gmv FROM order_items GROUP BY order_id
),
first_p AS (
    SELECT customer_unique_id, min(ts) AS first_ts FROM purchases GROUP BY customer_unique_id
),
buyer_value AS (
    SELECT f.customer_unique_id, f.first_ts,
           sum(g.gmv) FILTER (WHERE p.ts <= f.first_ts + interval '30 days')  AS gmv_30d,
           sum(g.gmv) FILTER (WHERE p.ts <= f.first_ts + interval '180 days') AS gmv_180d,
           sum(g.gmv) FILTER (WHERE p.ts <= f.first_ts + interval '365 days') AS gmv_365d
    FROM first_p f
    JOIN purchases p USING (customer_unique_id)
    JOIN order_gmv g USING (order_id)
    GROUP BY f.customer_unique_id, f.first_ts
)
SELECT '180 дней' AS window,
       count(*) AS buyers,
       round(avg(gmv_30d), 2)  AS avg_first_month_gmv,
       round(avg(gmv_180d), 2) AS ltv_gmv,
       round(100 * (avg(gmv_180d) / avg(gmv_30d) - 1), 1) AS uplift_vs_30d_pct
FROM buyer_value
WHERE first_ts >= '2017-01-01' AND first_ts < '2018-03-01'
UNION ALL
SELECT '365 дней',
       count(*),
       round(avg(gmv_30d), 2),
       round(avg(gmv_365d), 2),
       round(100 * (avg(gmv_365d) / avg(gmv_30d) - 1), 1)
FROM buyer_value
WHERE first_ts >= '2017-01-01' AND first_ts < '2017-09-01';
