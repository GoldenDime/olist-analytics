-- 10_core_metrics.sql — базовые метрики по месяцам: GMV, заказы, покупатели, средний чек.
--
-- Определения (их нужно уметь назвать на интервью):
--   GMV (Gross Merchandise Value) — сумма стоимости проданных товаров, БЕЗ доставки.
--   Валидный заказ — любой, кроме canceled и unavailable.
--   AOV (Average Order Value, средний чек) = GMV / число заказов.
--   Покупатель — customer_unique_id (реальный человек).
-- Период — полные месяцы 2017-01 … 2018-08.
SET search_path TO olist;

-- CTE (WITH ...) — это именованный подзапрос, «временная таблица» на время запроса.
WITH valid_orders AS (
    SELECT o.order_id,
           c.customer_unique_id,
           date_trunc('month', o.order_purchase_timestamp)::date AS month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id      -- переходим к реальному человеку
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
order_value AS (                      -- стоимость товаров в каждом заказе
    SELECT order_id,
           sum(price)         AS goods_value,
           sum(freight_value) AS freight_value
    FROM order_items
    GROUP BY order_id
)
SELECT v.month,
       count(DISTINCT v.order_id)            AS orders,
       count(DISTINCT v.customer_unique_id)  AS buyers,
       round(sum(ov.goods_value))            AS gmv_brl,
       round(sum(ov.goods_value) / count(DISTINCT v.order_id), 2) AS aov_brl,
       round(100.0 * sum(ov.freight_value) / sum(ov.goods_value), 1) AS freight_pct_of_gmv
FROM valid_orders v
JOIN order_value ov ON ov.order_id = v.order_id   -- INNER JOIN отбрасывает заказы без позиций
GROUP BY v.month
ORDER BY v.month;

-- Итог за весь период (для README и резюме)
WITH valid_orders AS (
    SELECT o.order_id, c.customer_unique_id
    FROM orders o JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT count(DISTINCT v.order_id)           AS orders,
       count(DISTINCT v.customer_unique_id) AS buyers,
       round(sum(i.price))                  AS gmv_brl,
       round(sum(i.price) / count(DISTINCT v.order_id), 2) AS aov_brl,
       round(count(DISTINCT v.order_id)::numeric / count(DISTINCT v.customer_unique_id), 3) AS orders_per_buyer
FROM valid_orders v
JOIN order_items i ON i.order_id = v.order_id;
