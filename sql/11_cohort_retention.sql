-- 11_cohort_retention.sql — когортный retention.
--
-- Когорта = месяц ПЕРВОЙ покупки человека.
-- Retention месяца N = доля людей когорты, купивших снова ровно в N-й месяц после первого.
-- Первая покупка ищется по всей истории (включая 2016), чтобы «старый» клиент
-- не попал в когорту 2017 как новый.
SET search_path TO olist;

WITH purchases AS (                         -- все валидные покупки человека
    SELECT c.customer_unique_id,
           o.order_purchase_timestamp AS ts
    FROM orders o JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
first_purchase AS (
    SELECT customer_unique_id,
           date_trunc('month', min(ts))::date AS cohort
    FROM purchases
    GROUP BY customer_unique_id
),
activity AS (                               -- в каких месяцах после первой покупки человек был активен
    SELECT DISTINCT p.customer_unique_id,
           f.cohort,
           (extract(year  FROM age(date_trunc('month', p.ts), f.cohort)) * 12
          + extract(month FROM age(date_trunc('month', p.ts), f.cohort)))::int AS month_n
    FROM purchases p JOIN first_purchase f USING (customer_unique_id)
),
cohort_size AS (
    SELECT cohort, count(*) AS buyers FROM first_purchase GROUP BY cohort
)
SELECT a.cohort,
       s.buyers,
       round(100.0 * count(*) FILTER (WHERE month_n = 1) / s.buyers, 2) AS m1_pct,
       round(100.0 * count(*) FILTER (WHERE month_n = 2) / s.buyers, 2) AS m2_pct,
       round(100.0 * count(*) FILTER (WHERE month_n = 3) / s.buyers, 2) AS m3_pct,
       round(100.0 * count(*) FILTER (WHERE month_n = 6) / s.buyers, 2) AS m6_pct
FROM activity a JOIN cohort_size s USING (cohort)
WHERE a.cohort BETWEEN '2017-01-01' AND '2018-02-01'   -- у поздних когорт ещё нет 6 месяцев истории
GROUP BY a.cohort, s.buyers
ORDER BY a.cohort;

-- Повторная покупка в течение 90 и 180 дней после первой (когорты 2017-01 … 2018-02).
-- ВАЖНО: около 30% «вторых заказов» сделаны в течение часа после первого — это один
-- поход в магазин, разбитый на несколько заказов, а не возврат клиента.
-- Поэтому повторной считаем покупку, сделанную не раньше чем через 24 часа после первой.
WITH purchases AS (
    SELECT c.customer_unique_id, o.order_purchase_timestamp AS ts
    FROM orders o JOIN customers c USING (customer_id)
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
first_p AS (
    SELECT customer_unique_id, min(ts) AS first_ts
    FROM purchases GROUP BY customer_unique_id
),
next_p AS (                                  -- первая покупка спустя >= 24 ч
    SELECT f.customer_unique_id, f.first_ts,
           min(p.ts) FILTER (WHERE p.ts >= f.first_ts + interval '1 day') AS repeat_ts
    FROM first_p f JOIN purchases p USING (customer_unique_id)
    GROUP BY f.customer_unique_id, f.first_ts
)
SELECT count(*) AS buyers,
       count(*) FILTER (WHERE repeat_ts IS NOT NULL) AS repeaters_ever,
       round(100.0 * count(*) FILTER (WHERE repeat_ts <= first_ts + interval '90 days')  / count(*), 2) AS repeat_90d_pct,
       round(100.0 * count(*) FILTER (WHERE repeat_ts <= first_ts + interval '180 days') / count(*), 2) AS repeat_180d_pct,
       round(100.0 * count(*) FILTER (WHERE repeat_ts IS NOT NULL) / count(*), 2) AS repeat_ever_pct
FROM next_p
WHERE first_ts >= '2017-01-01' AND first_ts < '2018-03-01';
