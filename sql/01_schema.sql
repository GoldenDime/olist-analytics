-- 01_schema.sql — схема базы Olist (PostgreSQL 16)
-- Порядок создания: сначала справочники, потом таблицы, которые на них ссылаются.
DROP SCHEMA IF EXISTS olist CASCADE;
CREATE SCHEMA olist;
SET search_path TO olist;

-- Справочник перевода категорий (португальский -> английский)
CREATE TABLE category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

-- Покупатели. customer_id — id покупателя В КОНКРЕТНОМ заказе,
-- customer_unique_id — реальный человек (нужен для повторных покупок!)
CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,
    customer_unique_id       TEXT NOT NULL,
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           CHAR(2)
);
CREATE INDEX ON customers (customer_unique_id);

CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           CHAR(2)
);

-- Опечатки "lenght" в названиях колонок — из оригинального датасета, оставляем как есть
CREATE TABLE products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        INT,
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL REFERENCES customers,
    order_status                  TEXT NOT NULL,
    order_purchase_timestamp      TIMESTAMP NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

-- Позиции заказа: одна строка = одна единица товара
CREATE TABLE order_items (
    order_id            TEXT NOT NULL REFERENCES orders,
    order_item_id       INT  NOT NULL,
    product_id          TEXT NOT NULL REFERENCES products,
    seller_id           TEXT NOT NULL REFERENCES sellers,
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2) NOT NULL,
    freight_value       NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

-- Платежи: один заказ можно оплатить несколькими способами
CREATE TABLE order_payments (
    order_id             TEXT NOT NULL REFERENCES orders,
    payment_sequential   INT  NOT NULL,
    payment_type         TEXT NOT NULL,
    payment_installments INT,
    payment_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- Отзывы. В исходных данных review_id НЕ уникален (один отзыв на несколько заказов),
-- поэтому ключ составной.
CREATE TABLE order_reviews (
    review_id               TEXT NOT NULL,
    order_id                TEXT NOT NULL REFERENCES orders,
    review_score            SMALLINT NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    PRIMARY KEY (review_id, order_id)
);

-- Геолокация: много точек на один индекс, ключа нет. Для анализа не основная.
CREATE TABLE geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat             NUMERIC(18,14),
    geolocation_lng             NUMERIC(18,14),
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);
