# ER-схема Olist

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : "делает"
    ORDERS ||--|{ ORDER_ITEMS : "содержит"
    ORDERS ||--o{ ORDER_PAYMENTS : "оплачивается"
    ORDERS ||--o{ ORDER_REVIEWS : "получает"
    PRODUCTS ||--o{ ORDER_ITEMS : "входит в"
    SELLERS ||--o{ ORDER_ITEMS : "продаёт"
    CATEGORY_TRANSLATION ||--o{ PRODUCTS : "переводит категорию"

    CUSTOMERS {
        text customer_id PK "id покупателя в заказе"
        text customer_unique_id "реальный человек"
        text customer_state
    }
    ORDERS {
        text order_id PK
        text customer_id FK
        text order_status
        timestamp order_purchase_timestamp
        timestamp order_delivered_customer_date
        timestamp order_estimated_delivery_date
    }
    ORDER_ITEMS {
        text order_id PK,FK
        int order_item_id PK
        text product_id FK
        text seller_id FK
        numeric price
        numeric freight_value
    }
    ORDER_PAYMENTS {
        text order_id PK,FK
        int payment_sequential PK
        text payment_type
        numeric payment_value
    }
    ORDER_REVIEWS {
        text review_id PK
        text order_id PK,FK
        smallint review_score
    }
    PRODUCTS {
        text product_id PK
        text product_category_name
    }
    SELLERS {
        text seller_id PK
        text seller_state
    }
    CATEGORY_TRANSLATION {
        text product_category_name PK
        text product_category_name_english
    }
```

`geolocation` на схеме не показана: у неё нет ключа (несколько координат на один почтовый индекс), с остальными таблицами она связывается только по `zip_code_prefix` и в основных метриках не участвует.

## Как читать связи

- `||--o{` — «один ко многим, может быть ноль»: у покупателя-в-заказе может быть ноль или больше заказов.
- `||--|{` — «один ко многим, минимум один»: у заказа по смыслу есть хотя бы одна позиция (на деле 775 заказов без позиций — см. качество данных).
- **Главная ловушка:** `customer_id` новый в каждом заказе. Чтобы найти повторного покупателя, нужно идти в `customers.customer_unique_id`. Если считать по `customer_id`, повторных покупок будет ровно ноль.
