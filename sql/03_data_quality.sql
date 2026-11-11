-- 03_data_quality.sql — проверки качества данных после загрузки.
-- Зачем: прежде чем считать метрики, надо понять, где в данных «дыры»,
-- иначе на интервью спросят «а вы учли отменённые заказы?» и ответить будет нечего.
SET search_path TO olist;

-- 1. Период данных
SELECT min(order_purchase_timestamp) AS first_order,
       max(order_purchase_timestamp) AS last_order
FROM orders;

-- 2. Заказов по месяцам: видно неполные месяцы на краях (2016-09..12, 2018-09..10)
SELECT date_trunc('month', order_purchase_timestamp)::date AS month,
       count(*) AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

-- 3. Статусы заказов
SELECT order_status, count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM orders
GROUP BY 1
ORDER BY 2 DESC;

-- 4. Люди vs id покупателя в заказе
SELECT count(*)                           AS customer_ids,
       count(DISTINCT customer_unique_id) AS unique_people
FROM customers;

-- 5. Заказы без позиций и без оплаты
SELECT
  (SELECT count(*) FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id))    AS orders_without_items,
  (SELECT count(*) FROM orders o
    WHERE NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id)) AS orders_without_payments;

-- 6. Заказы с несколькими отзывами
SELECT count(*) AS orders_with_several_reviews
FROM (SELECT order_id FROM order_reviews GROUP BY order_id HAVING count(*) > 1) t;

-- 7. Доставленные заказы без даты доставки
SELECT count(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- 8. Расхождение «сумма позиций + доставка» vs «сумма платежей» по заказу
WITH items AS (
  SELECT order_id, sum(price + freight_value) AS items_total
  FROM order_items GROUP BY order_id
), pays AS (
  SELECT order_id, sum(payment_value) AS paid_total
  FROM order_payments GROUP BY order_id
)
SELECT count(*) AS orders_compared,
       count(*) FILTER (WHERE abs(items_total - paid_total) > 1) AS mismatch_over_1_brl
FROM items JOIN pays USING (order_id);
