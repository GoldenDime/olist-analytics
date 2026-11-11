"""Юнит-экономика покупателя Olist за 12 месяцев со сценариями.

ФАКТЫ берутся из базы (когорты первой покупки 01.2017–08.2017, у всех есть 365 дней истории).
ДОПУЩЕНИЯ вынесены в блок ниже: в датасете их нет, на интервью их надо называть допущениями.
Запуск из корня репозитория:  python3 scripts/unit_economics.py > docs/unit-economics-table.md
"""
import subprocess

# ---------- ДОПУЩЕНИЯ (в данных их нет) ----------
TAKE_RATES = [0.10, 0.15, 0.20]   # комиссия маркетплейса с GMV
PAYMENT_FEE = 0.025               # эквайринг: % от суммы оплаты (товары + доставка)
OPS_COST_PER_ORDER = 2.0          # поддержка и операционка, R$ на заказ
REPEAT_SCENARIOS = [0.0, 0.02, 0.05]  # прирост доли повторных покупателей, п.п.

# ---------- ФАКТЫ из базы ----------
SQL = """
SET search_path TO olist;
WITH p AS (SELECT c.customer_unique_id u, o.order_id, o.order_purchase_timestamp ts
           FROM orders o JOIN customers c USING (customer_id)
           WHERE o.order_status NOT IN ('canceled','unavailable')),
it AS (SELECT order_id, sum(price) g, sum(freight_value) fr FROM order_items GROUP BY 1),
f AS (SELECT u, min(ts) f FROM p GROUP BY u),
b AS (SELECT f.u, count(*) n, sum(g) g, sum(fr) fr,
             count(*) FILTER (WHERE p.ts >= f.f + interval '1 day') rep
      FROM f JOIN p USING (u) JOIN it USING (order_id)
      WHERE p.ts <= f.f + interval '365 days'
        AND f.f >= '2017-01-01' AND f.f < '2017-09-01'
      GROUP BY 1)
SELECT count(*), avg(n), avg(g), avg(fr), avg((rep > 0)::int),
       avg(g)  FILTER (WHERE rep > 0), avg(g)  FILTER (WHERE rep = 0),
       avg(n)  FILTER (WHERE rep > 0), avg(n)  FILTER (WHERE rep = 0),
       avg(fr) FILTER (WHERE rep > 0), avg(fr) FILTER (WHERE rep = 0)
FROM b;
"""
out = subprocess.run(["psql", "-d", "olist", "-Atc", SQL], capture_output=True, text=True, check=True).stdout
vals = [float(x) for x in out.strip().splitlines()[-1].split("|")]
buyers, orders, gmv, freight, repeat_share, gmv_rep, gmv_one, n_rep, n_one, fr_rep, fr_one = vals


def contribution(gmv, freight, orders, take):
    """Маржинальный доход Olist с одного покупателя за 12 мес. = максимальный CAC с окупаемостью за год."""
    revenue = take * gmv
    costs = PAYMENT_FEE * (gmv + freight) + OPS_COST_PER_ORDER * orders
    return revenue, costs, revenue - costs


print("## Факты (когорты 01.2017–08.2017, 365 дней)\n")
print("| Показатель | Значение |\n|---|---|")
print(f"| Покупателей | {buyers:,.0f} |".replace(",", " "))
print(f"| Заказов на покупателя | {orders:.3f} |")
print(f"| GMV на покупателя | {gmv:.2f} R$ |")
print(f"| Доставка на покупателя | {freight:.2f} R$ |")
print(f"| Доля вернувшихся (≥24 ч) | {repeat_share:.2%} |")
print(f"| GMV вернувшегося / разового | {gmv_rep:.2f} / {gmv_one:.2f} R$ |")

print("\n## Базовый сценарий: юнит-экономика покупателя\n")
print("| Комиссия | Выручка Olist | Эквайринг + операционка | Маржинальный доход = макс. CAC |\n|---|---|---|---|")
for t in TAKE_RATES:
    r, c, m = contribution(gmv, freight, orders, t)
    print(f"| {t:.0%} | {r:.2f} R$ | {c:.2f} R$ | **{m:.2f} R$** |")

print("\n## Сценарии роста повторных покупок: макс. CAC\n")
header = " | ".join(f"комиссия {t:.0%}" for t in TAKE_RATES)
print(f"| Доля вернувшихся | {header} |\n|---|" + "---|" * len(TAKE_RATES))
for d in REPEAT_SCENARIOS:
    s = repeat_share + d
    g = s * gmv_rep + (1 - s) * gmv_one
    fr = s * fr_rep + (1 - s) * fr_one
    n = s * n_rep + (1 - s) * n_one
    cells = []
    for t in TAKE_RATES:
        m = contribution(g, fr, n, t)[2]
        base = contribution(gmv, freight, orders, t)[2]
        cells.append(f"{m:.2f} R$ ({(m / base - 1):+.1%})")
    label = "факт" if d == 0 else f"+{d * 100:.0f} п.п."
    print(f"| {s:.2%} ({label}) | " + " | ".join(cells) + " |")
