#!/usr/bin/env bash
# Скачивает датасет Olist (официальный репозиторий olist/work-at-olist-data, лицензия MIT)
# и загружает его в локальную базу PostgreSQL `olist`.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
git clone --depth 1 https://github.com/olist/work-at-olist-data.git "$tmp/olist"
mkdir -p data/raw
cp "$tmp"/olist/datasets/*.csv data/raw/
sed -i '1s/^\xEF\xBB\xBF//' data/raw/product_category_name_translation.csv   # убрать BOM
createdb olist 2>/dev/null || true
psql -d olist -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -d olist -v ON_ERROR_STOP=1 -f sql/02_load.sql
echo "Готово. Проверки: psql -d olist -f sql/03_data_quality.sql"
