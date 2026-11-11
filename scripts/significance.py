"""Z-тест для двух долей: значимо ли различается доля повторных покупок между группами.
Запуск из корня репозитория:  python3 scripts/significance.py
Нужна база olist с view first_orders (sql/20_delivery_reviews.sql)."""
import math, subprocess

TESTS = {
    "Опоздание (delay_days > 0)":             "delay_days > 0",
    "Доставка 21+ дней vs до 7 дней":         "CASE WHEN delivery_days >= 21 THEN true WHEN delivery_days < 7 THEN false END",
    "Плохой отзыв (1–2) vs остальные":        "CASE WHEN review_score IS NULL THEN NULL ELSE review_score <= 2 END",
}

def query(expr):
    sql = (f"SET search_path TO olist; SELECT ({expr}) AS g, count(*), sum(repeat_180d::int) "
           f"FROM first_orders WHERE ({expr}) IS NOT NULL GROUP BY 1 ORDER BY 1;")
    out = subprocess.run(["psql", "-d", "olist", "-Atc", sql], capture_output=True, text=True, check=True).stdout
    rows = [l.split("|") for l in out.split() if "|" in l]
    return [(int(n), int(x)) for _, n, x in rows]       # [(n, повторные) для false, для true]

for name, expr in TESTS.items():
    (n1, x1), (n2, x2) = query(expr)
    p1, p2 = x1 / n1, x2 / n2
    p = (x1 + x2) / (n1 + n2)
    se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2))
    z = (p2 - p1) / se
    pval = math.erfc(abs(z) / math.sqrt(2))              # двусторонний p-value
    print(f"{name}\n  контроль: {p1:.2%} (n={n1}), группа: {p2:.2%} (n={n2}), "
          f"разница {100*(p2-p1):+.2f} п.п., z={z:.2f}, p={pval:.4f}")
