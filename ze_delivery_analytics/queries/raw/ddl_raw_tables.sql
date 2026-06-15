-- =============================================================
-- DDL - Camada RAW - BigQuery
-- Projeto   : analytics-project-499319
-- Dataset   : ze_delivery_project
-- Prefixo   : raw_
--
-- Tabelas espelho dos CSVs originais, sem nenhuma transformação.
-- Carga feita via bq load (ver load_raw_bq.sh)
-- =============================================================

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_customers`
(
  customer_id   STRING  NOT NULL,
  customer_name STRING,
  signup_date   DATE,
  country       STRING
)
OPTIONS (description = 'Cadastro de clientes - carga bruta do CSV customers_1.csv');

-- -------------------------------------------------------------

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_products`
(
  product_id   STRING  NOT NULL,
  product_name STRING,
  category     STRING,
  list_price   NUMERIC
)
OPTIONS (description = 'Catálogo de produtos - carga bruta do CSV products_1.csv');

-- -------------------------------------------------------------

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_orders`
(
  order_id    STRING  NOT NULL,
  customer_id STRING  NOT NULL,
  order_date  DATE    NOT NULL,
  status      STRING,
  canceled_at DATE
)
OPTIONS (description = 'Pedidos - carga bruta do CSV orders_1.csv');

-- -------------------------------------------------------------

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_order_items`
(
  order_item_id STRING  NOT NULL,
  order_id      STRING  NOT NULL,
  product_id    STRING  NOT NULL,
  quantity      INT64   NOT NULL,
  unit_price    NUMERIC NOT NULL
)
OPTIONS (description = 'Itens dos pedidos - carga bruta do CSV order_items_1.csv');

-- -------------------------------------------------------------

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_payments`
(
  payment_id     STRING  NOT NULL,
  order_id       STRING  NOT NULL,
  payment_date   DATE,
  payment_method STRING,
  payment_status STRING,
  amount         NUMERIC
)
OPTIONS (description = 'Pagamentos - carga bruta do CSV payments_1.csv');

-- -------------------------------------------------------------

CREATE OR REPLACE TABLE `analytics-project-499319.ze_delivery_project.raw_refunds`
(
  refund_id   STRING  NOT NULL,
  order_id    STRING  NOT NULL,
  refund_date DATE,
  amount      NUMERIC,
  reason      STRING
)
OPTIONS (description = 'Reembolsos - carga bruta do CSV refunds_1.csv');
