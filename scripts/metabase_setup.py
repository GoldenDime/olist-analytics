"""Создаёт в Metabase подключение к базе olist, вопросы (карточки) и дашборд «Olist: рост и удержание».
Запуск: docker compose up -d, дождаться http://localhost:3000, затем  python3 scripts/metabase_setup.py
Логин в Metabase после запуска: admin@example.com / OlistDemo2026!  (локальная демо-учётка)
"""
import json, time, urllib.request

MB = "http://localhost:3000"
ADMIN = {"email": "admin@example.com", "password": "OlistDemo2026!", "first_name": "Olist", "last_name": "Demo"}
DB = {"engine": "postgres", "name": "Olist",
      "details": {"host": "127.0.0.1", "port": 5432, "dbname": "olist", "user": "metabase",
                  "password": "metabase", "schema-filters-type": "inclusion",
                  "schema-filters-patterns": "olist"}}
session = None

def api(method, path, body=None):
    req = urllib.request.Request(MB + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json",
                                          **({"X-Metabase-Session": session} if session else {})})
    with urllib.request.urlopen(req) as r:
        txt = r.read()
        return json.loads(txt) if txt else None

props = api("GET", "/api/session/properties")
if props.get("setup-token") and not props.get("has-user-setup"):
    session = api("POST", "/api/setup", {"token": props["setup-token"], "user": ADMIN,
                                         "prefs": {"site_name": "Olist analytics", "allow_tracking": False}})["id"]
else:
    session = api("POST", "/api/session", {"username": ADMIN["email"], "password": ADMIN["password"]})["id"]

db = next((d for d in api("GET", "/api/database")["data"] if d["name"] == "Olist"), None) or api("POST", "/api/database", DB)
db_id = db["id"]

def card(name, sql, display, viz=None):
    return api("POST", "/api/card", {"name": name, "display": display, "visualization_settings": viz or {},
                                     "dataset_query": {"type": "native", "database": db_id,
                                                       "native": {"query": sql}}})["id"]

S = "SELECT * FROM olist."
cards = [  # (id, col, row, size_x, size_y)
    (card("Заказы (01.2017–08.2018)", "SELECT orders FROM olist.v_kpi", "scalar"), 0, 0, 6, 3),
    (card("GMV, R$", "SELECT gmv FROM olist.v_kpi", "scalar"), 6, 0, 6, 3),
    (card("Средний чек, R$", "SELECT aov FROM olist.v_kpi", "scalar"), 12, 0, 6, 3),
    (card("Повторная покупка за 180 дней, %", "SELECT repeat_180d_pct FROM olist.v_kpi", "scalar"), 18, 0, 6, 3),
    (card("GMV и заказы по месяцам", S + "v_monthly ORDER BY month", "combo",
          {"graph.dimensions": ["month"], "graph.metrics": ["gmv", "orders"],
           "series_settings": {"gmv": {"display": "bar"}, "orders": {"display": "line", "axis": "right"}}}), 0, 3, 16, 7),
    (card("Средний чек по месяцам, R$", S + "v_monthly ORDER BY month", "line",
          {"graph.dimensions": ["month"], "graph.metrics": ["aov"]}), 16, 3, 8, 7),
    (card("Когортный retention, % вернувшихся в месяц N после первой покупки",
          S + "v_cohort_wide ORDER BY cohort", "table",
          {"table.column_formatting": [{"columns": ["m1", "m2", "m3", "m4", "m5", "m6"], "type": "range",
                                        "colors": ["white", "#509EE3"], "min_type": None, "max_type": None,
                                        "highlight_row": False}]}), 0, 10, 24, 9),
    (card("Опоздание доставки → доля плохих оценок, %", S + "v_delay_effect ORDER BY delivery", "bar",
          {"graph.dimensions": ["delivery"], "graph.metrics": ["bad_review_pct"]}), 0, 19, 12, 7),
    (card("Срок доставки → повторная покупка за 180 дней, %", S + "v_delivery_time_effect ORDER BY delivery_time", "bar",
          {"graph.dimensions": ["delivery_time"], "graph.metrics": ["repeat_180d_pct"]}), 12, 19, 12, 7),
    (card("Топ-10 категорий по GMV, R$", S + "v_categories ORDER BY gmv DESC LIMIT 10", "row",
          {"graph.dimensions": ["category"], "graph.metrics": ["gmv"]}), 0, 26, 24, 8),
]

dash = api("POST", "/api/dashboard", {"name": "Olist: рост и удержание",
                                      "description": "Данные Olist 01.2017–08.2018. Расчёты — SQL-витрины из sql/30_dashboard_views.sql."})
api("PUT", f"/api/dashboard/{dash['id']}", {"dashcards": [
    {"id": -(i + 1), "card_id": cid, "col": c, "row": r, "size_x": w, "size_y": h,
     "parameter_mappings": [], "visualization_settings": {}}
    for i, (cid, c, r, w, h) in enumerate(cards)]})
print(f"Готово: {MB}/dashboard/{dash['id']}")
