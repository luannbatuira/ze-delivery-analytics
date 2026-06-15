-- =============================================================
-- DDL - Camada STAGING - BigQuery (views)
-- Projeto   : analytics-project-499319
-- Dataset   : ze_delivery_project
-- Prefixo   : stg_
--
-- Aplicam regras de negócio, limpeza e diagnóstico de qualidade.
-- Todas são views — compatível com free tier do BQ.
-- Execute um bloco CREATE OR REPLACE VIEW por vez no BQ Studio.
-- =============================================================


-- ------------------------------------------------------------
-- BASE: dimensões e filtros fundamentais (rodar primeiro)
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dim_products` AS
SELECT
  product_id,
  product_name,
  CASE
    WHEN TRIM(COALESCE(category, '')) = '' THEN 'Sem Categoria'
    ELSE category
  END AS category,
  list_price
FROM `analytics-project-499319.ze_delivery_project.raw_products`;

-- ------------------------------------------------------------

CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_payments_captured` AS
SELECT
  order_id,
  SUM(amount) AS total_captured
FROM `analytics-project-499319.ze_delivery_project.raw_payments`
WHERE payment_status = 'captured'
GROUP BY order_id;

-- ------------------------------------------------------------

CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS
SELECT
  o.order_id,
  o.customer_id,
  o.order_date,
  o.status,
  FORMAT_DATE('%Y-%m', o.order_date) AS order_month,
  pc.total_captured
FROM `analytics-project-499319.ze_delivery_project.raw_orders` AS o
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_payments_captured` AS pc
  ON o.order_id = pc.order_id
WHERE o.status <> 'canceled';

-- ------------------------------------------------------------

CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS
SELECT
  oi.order_id,
  SUM(oi.quantity * oi.unit_price) AS gross_revenue
FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
  ON oi.order_id = vo.order_id
GROUP BY oi.order_id;

-- ------------------------------------------------------------

CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS
SELECT
  order_id,
  SUM(amount) AS total_refunded
FROM `analytics-project-499319.ze_delivery_project.raw_refunds`
GROUP BY order_id;


-- ------------------------------------------------------------
-- ANALÍTICAS: respostas às questões de negócio
-- ------------------------------------------------------------

-- Q1: Receita líquida por mês
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_q1_net_revenue_by_month` AS
SELECT
  vo.order_month,
  SUM(ogr.gross_revenue)                         AS gross_revenue,
  COALESCE(SUM(orr.total_refunded), 0)           AS total_refunds,
  SUM(ogr.gross_revenue)
    - COALESCE(SUM(orr.total_refunded), 0)       AS net_revenue
FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr
  ON vo.order_id = ogr.order_id
LEFT JOIN `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS orr
  ON vo.order_id = orr.order_id
GROUP BY vo.order_month
ORDER BY vo.order_month;

-- ------------------------------------------------------------

-- Q2: Primeiras compras válidas por mês
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_q2_new_customers_by_month` AS
WITH first_valid_order AS (
  SELECT
    customer_id,
    MIN(order_date)                       AS first_order_date,
    FORMAT_DATE('%Y-%m', MIN(order_date)) AS first_order_month
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders`
  GROUP BY customer_id
)
SELECT
  first_order_month AS order_month,
  COUNT(customer_id) AS new_customers
FROM first_valid_order
GROUP BY first_order_month
ORDER BY first_order_month;

-- ------------------------------------------------------------

-- Q3: Receita bruta por categoria
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_q3_gross_revenue_by_category` AS
SELECT
  p.category,
  SUM(oi.quantity * oi.unit_price) AS gross_revenue
FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
  ON oi.order_id = vo.order_id
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_dim_products` AS p
  ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY gross_revenue DESC;

-- ------------------------------------------------------------

-- Q4: Ticket médio de pedidos válidos
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_q4_avg_ticket` AS
SELECT
  COUNT(DISTINCT ogr.order_id)                   AS total_valid_orders,
  SUM(ogr.gross_revenue)                         AS total_gross_revenue,
  ROUND(
    SUM(ogr.gross_revenue) / COUNT(DISTINCT ogr.order_id), 2
  )                                              AS avg_ticket
FROM `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr;


-- ------------------------------------------------------------
-- DATA QUALITY: diagnóstico de problemas nos dados
-- ------------------------------------------------------------

-- DQ1: Pagamentos captured duplicados no mesmo pedido
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_duplicate_payments` AS
SELECT
  order_id,
  amount,
  COUNT(*) AS occurrences,
  'Possível pagamento duplicado (mesmo valor captured 2x)' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_payments`
WHERE payment_status = 'captured'
GROUP BY order_id, amount
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------

-- DQ2: Pedidos com mais de um status de pagamento
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_mixed_payment_status` AS
SELECT
  order_id,
  STRING_AGG(DISTINCT payment_status ORDER BY payment_status) AS payment_statuses,
  COUNT(*) AS payment_count,
  'Pedido com mais de um status de pagamento' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_payments`
GROUP BY order_id
HAVING COUNT(DISTINCT payment_status) > 1;

-- ------------------------------------------------------------

-- DQ3: Produtos sem categoria
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_products_no_category` AS
SELECT
  product_id,
  product_name,
  category,
  'Produto sem categoria definida' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_products`
WHERE TRIM(COALESCE(category, '')) = '';

-- ------------------------------------------------------------

-- DQ4: Divergência entre unit_price e list_price
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_price_divergence` AS
SELECT
  oi.order_item_id,
  oi.order_id,
  oi.product_id,
  oi.unit_price                           AS sold_price,
  p.list_price,
  ROUND(oi.unit_price - p.list_price, 2) AS price_diff,
  'unit_price difere do list_price do produto' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
INNER JOIN `analytics-project-499319.ze_delivery_project.raw_products` AS p
  ON oi.product_id = p.product_id
WHERE oi.unit_price <> p.list_price;

-- ------------------------------------------------------------

-- DQ5: Pedidos cancelados com pagamento captured
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_canceled_with_capture` AS
SELECT
  o.order_id,
  o.status,
  o.canceled_at,
  p.payment_status,
  p.amount,
  'Pedido cancelado mas com pagamento captured' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_orders` AS o
INNER JOIN `analytics-project-499319.ze_delivery_project.raw_payments` AS p
  ON o.order_id = p.order_id
WHERE o.status = 'canceled'
  AND p.payment_status = 'captured';

-- ------------------------------------------------------------

-- DQ6: Reembolsos em pedidos cancelados
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.stg_dq_refunds_on_canceled` AS
SELECT
  r.refund_id,
  r.order_id,
  r.amount,
  r.reason,
  o.status,
  'Reembolso registrado em pedido com status canceled' AS issue
FROM `analytics-project-499319.ze_delivery_project.raw_refunds` AS r
INNER JOIN `analytics-project-499319.ze_delivery_project.raw_orders` AS o
  ON r.order_id = o.order_id
WHERE o.status = 'canceled';
