-- 20_delivery_reviews.sql — как доставка и отзывы связаны с повторной покупкой.
--
-- Берём ПЕРВЫЙ заказ каждого человека (когорты 2017-01 … 2018-02, чтобы было 180 дней истории),
-- только доставленные с известной датой доставки.
-- Повторная покупка — не раньше чем через 24 ч после первой и не позже 180 дней.
SET search_path TO olist;

DROP VIEW IF EXISTS first_orders;
CREATE VIEW first_orders AS
WITH purchases AS (
    SELECT c.customer_unique_id, o.*
    FROM orders o JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
ranked AS (
    SELECT *, row_number() OVER (PARTITION BY customer_unique_id
                                 ORDER BY order_purchase_timestamp) AS rn
    FROM purchases
),
reviews AS (                                   -- средний балл, если отзывов несколько
    SELECT order_id, avg(review_score) AS review_score
    FROM order_reviews GROUP BY order_id
),
repeats AS (                                   -- была ли покупка через 24 ч … 180 дней после первой
    SELECT f.customer_unique_id, true AS has_repeat
    FROM ranked f
    JOIN purchases p ON p.customer_unique_id = f.customer_unique_id
    WHERE f.rn = 1
      AND p.order_purchase_timestamp >= f.order_purchase_timestamp + interval '1 day'
      AND p.order_purchase_timestamp <= f.order_purchase_timestamp + interval '180 days'
    GROUP BY f.customer_unique_id
)
SELECT f.customer_unique_id,
       f.order_id,
       f.order_purchase_timestamp AS first_ts,
       -- срок доставки в днях
       extract(epoch FROM f.order_delivered_customer_date - f.order_purchase_timestamp) / 86400 AS delivery_days,
       -- опоздание: >0 — привезли позже обещанной даты
       f.order_delivered_customer_date::date - f.order_estimated_delivery_date::date AS delay_days,
       r.review_score,
       coalesce(rp.has_repeat, false) AS repeat_180d
FROM ranked f
LEFT JOIN reviews r ON r.order_id = f.order_id
LEFT JOIN repeats rp ON rp.customer_unique_id = f.customer_unique_id
WHERE f.rn = 1
  AND f.order_status = 'delivered'
  AND f.order_delivered_customer_date IS NOT NULL
  AND f.order_purchase_timestamp >= '2017-01-01'
  AND f.order_purchase_timestamp <  '2018-03-01';

-- 1. Опоздание -> оценка и повторная покупка
SELECT CASE WHEN delay_days <= -10 THEN '1. на 10+ дней раньше'
            WHEN delay_days <= 0   THEN '2. вовремя (0–9 дн. раньше)'
            WHEN delay_days <= 7   THEN '3. опоздание 1–7 дн.'
            ELSE                        '4. опоздание 8+ дн.' END AS delivery,
       count(*)                                   AS first_orders,
       round(avg(review_score), 2)                AS avg_review,
       round(100.0 * avg((review_score <= 2)::int), 1) AS bad_review_pct,
       round(100.0 * avg(repeat_180d::int), 2)    AS repeat_180d_pct
FROM first_orders
GROUP BY 1 ORDER BY 1;

-- 2. Оценка первого заказа -> повторная покупка
SELECT CASE WHEN review_score IS NULL THEN 'нет отзыва'
            ELSE round(review_score)::text END AS review,
       count(*) AS first_orders,
       round(100.0 * avg(repeat_180d::int), 2) AS repeat_180d_pct
FROM first_orders
GROUP BY 1 ORDER BY 1;

-- 3. Срок доставки -> повторная покупка
SELECT CASE WHEN delivery_days < 7  THEN '1. до 7 дней'
            WHEN delivery_days < 14 THEN '2. 7–13 дней'
            WHEN delivery_days < 21 THEN '3. 14–20 дней'
            ELSE                         '4. 21+ день' END AS delivery_time,
       count(*) AS first_orders,
       round(avg(review_score), 2) AS avg_review,
       round(100.0 * avg(repeat_180d::int), 2) AS repeat_180d_pct
FROM first_orders
GROUP BY 1 ORDER BY 1;
