#!/bin/bash
# =============================================================
# Carga das tabelas RAW via bq load (compatível com free tier)
# Projeto   : analytics-project-499319
# Dataset   : ze_delivery_project
#
# Pré-requisitos:
#   1. gcloud CLI instalado e autenticado
#   2. CSVs no mesmo diretório deste script
#   3. Tabelas raw_* já criadas via ddl_raw_tables.sql
#
# Uso:
#   chmod +x load_raw_bq.sh
#   ./load_raw_bq.sh
# =============================================================

PROJECT="analytics-project-499319"
DATASET="ze_delivery_project"
DIR="$(dirname "$0")"

echo "========================================="
echo " Iniciando carga RAW - $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

load_table() {
  local table=$1
  local file=$2
  local schema=$3
  echo ""
  echo ">>> Carregando $table ..."
  bq load \
    --project_id="$PROJECT" \
    --replace \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --null_marker="" \
    "${DATASET}.${table}" \
    "${DIR}/${file}" \
    "$schema"
  if [ $? -eq 0 ]; then
    echo "    OK: $table carregada com sucesso."
  else
    echo "    ERRO: falha ao carregar $table."
    exit 1
  fi
}

load_table "raw_customers"   "customers 1.csv"   "customer_id:STRING,customer_name:STRING,signup_date:DATE,country:STRING"
load_table "raw_products"    "products 1.csv"    "product_id:STRING,product_name:STRING,category:STRING,list_price:NUMERIC"
load_table "raw_orders"      "orders 1.csv"      "order_id:STRING,customer_id:STRING,order_date:DATE,status:STRING,canceled_at:DATE"
load_table "raw_order_items" "order_items 1.csv" "order_item_id:STRING,order_id:STRING,product_id:STRING,quantity:INTEGER,unit_price:NUMERIC"
load_table "raw_payments"    "payments 1.csv"    "payment_id:STRING,order_id:STRING,payment_date:DATE,payment_method:STRING,payment_status:STRING,amount:NUMERIC"
load_table "raw_refunds"     "refunds 1.csv"     "refund_id:STRING,order_id:STRING,refund_date:DATE,amount:NUMERIC,reason:STRING"

echo ""
echo "========================================="
echo " Carga finalizada - $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
