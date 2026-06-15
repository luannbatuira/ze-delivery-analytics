-- =============================================================
-- DDL - Camada TRUSTED - BigQuery (views)
-- Projeto   : analytics-project-499319
-- Dataset   : ze_delivery_project
-- Prefixo   : trusted_
--
-- Views analíticas consolidadas, prontas para consumo por BI
-- e stakeholders. Compatível com free tier do BQ.
-- Execute um bloco CREATE OR REPLACE VIEW por vez no BQ Studio.
-- =============================================================


-- ------------------------------------------------------------
-- trusted_daily_revenue
-- Granularidade: 1 linha por dia com pedidos válidos
-- Uso: gráficos diários, detecção de anomalias
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.trusted_daily_revenue` AS
WITH valid_orders_revenue AS (
  SELECT
    vo.order_id,
    vo.customer_id,
    vo.order_date,
    ogr.gross_revenue,
    COALESCE(orr.total_refunded, 0) AS order_refund
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr
    ON vo.order_id = ogr.order_id
  LEFT JOIN `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS orr
    ON vo.order_id = orr.order_id
),
items_per_order AS (
  SELECT
    oi.order_id,
    SUM(oi.quantity) AS items_sold
  FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
    ON oi.order_id = vo.order_id
  GROUP BY oi.order_id
),
first_purchase AS (
  SELECT
    customer_id,
    MIN(order_date) AS first_order_date
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders`
  GROUP BY customer_id
),
order_grain AS (
  SELECT
    vor.order_date,
    vor.order_id,
    vor.customer_id,
    vor.gross_revenue,
    vor.order_refund,
    COALESCE(ipo.items_sold, 0) AS items_sold,
    CASE WHEN fp.first_order_date = vor.order_date THEN 1 ELSE 0 END AS is_new_customer
  FROM valid_orders_revenue AS vor
  LEFT JOIN items_per_order AS ipo ON vor.order_id    = ipo.order_id
  LEFT JOIN first_purchase  AS fp  ON vor.customer_id = fp.customer_id
)
SELECT
  order_date,
  EXTRACT(YEAR  FROM order_date)                          AS order_year,
  FORMAT_DATE('%Y-%m',  order_date)                       AS order_month,
  FORMAT_DATE('%Y-W%V', order_date)                       AS order_week,
  FORMAT_DATE('%A',     order_date)                       AS day_of_week,
  COUNT(DISTINCT order_id)                                AS total_orders,
  SUM(items_sold)                                         AS total_items_sold,
  SUM(gross_revenue)                                      AS gross_revenue,
  SUM(order_refund)                                       AS total_refunds,
  SUM(gross_revenue) - SUM(order_refund)                  AS net_revenue,
  COUNT(DISTINCT customer_id)                             AS total_customers,
  SUM(is_new_customer)                                    AS new_customers,
  ROUND(SUM(gross_revenue) / COUNT(DISTINCT order_id), 2) AS avg_ticket
FROM order_grain
GROUP BY order_date
ORDER BY order_date;


-- ------------------------------------------------------------
-- trusted_monthly_revenue
-- Granularidade: 1 linha por mês civil
-- Uso: relatórios executivos, metas mensais, variação MoM
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.trusted_monthly_revenue` AS
WITH valid_orders_revenue AS (
  SELECT
    vo.order_id,
    vo.customer_id,
    vo.order_date,
    FORMAT_DATE('%Y-%m', vo.order_date) AS order_month,
    ogr.gross_revenue,
    COALESCE(orr.total_refunded, 0)     AS order_refund
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr
    ON vo.order_id = ogr.order_id
  LEFT JOIN `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS orr
    ON vo.order_id = orr.order_id
),
items_per_order AS (
  SELECT
    oi.order_id,
    SUM(oi.quantity) AS items_sold
  FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
    ON oi.order_id = vo.order_id
  GROUP BY oi.order_id
),
first_purchase AS (
  SELECT
    customer_id,
    FORMAT_DATE('%Y-%m', MIN(order_date)) AS first_order_month
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders`
  GROUP BY customer_id
),
top_category_per_month AS (
  SELECT
    order_month,
    category,
    ROW_NUMBER() OVER (
      PARTITION BY order_month
      ORDER BY cat_revenue DESC
    ) AS rn
  FROM (
    SELECT
      FORMAT_DATE('%Y-%m', vo.order_date) AS order_month,
      p.category,
      SUM(oi.quantity * oi.unit_price)    AS cat_revenue
    FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
    INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
      ON oi.order_id = vo.order_id
    INNER JOIN `analytics-project-499319.ze_delivery_project.stg_dim_products` AS p
      ON oi.product_id = p.product_id
    GROUP BY order_month, p.category
  )
),
monthly_base AS (
  SELECT
    vor.order_month,
    EXTRACT(YEAR  FROM PARSE_DATE('%Y-%m', vor.order_month)) AS order_year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y-%m', vor.order_month)) AS month_number,
    FORMAT_DATE('%B', PARSE_DATE('%Y-%m', vor.order_month))  AS month_name,
    COUNT(DISTINCT vor.order_id)                             AS total_orders,
    SUM(COALESCE(ipo.items_sold, 0))                         AS total_items_sold,
    SUM(vor.gross_revenue)                                   AS gross_revenue,
    SUM(vor.order_refund)                                    AS total_refunds,
    SUM(vor.gross_revenue) - SUM(vor.order_refund)           AS net_revenue,
    COUNT(DISTINCT vor.customer_id)                          AS total_customers,
    COUNT(DISTINCT CASE
      WHEN fp.first_order_month = vor.order_month
      THEN vor.customer_id END)                              AS new_customers,
    ROUND(SUM(vor.gross_revenue) / COUNT(DISTINCT vor.order_id), 2) AS avg_ticket
  FROM valid_orders_revenue AS vor
  LEFT JOIN items_per_order AS ipo ON vor.order_id    = ipo.order_id
  LEFT JOIN first_purchase  AS fp  ON vor.customer_id = fp.customer_id
  GROUP BY vor.order_month
)
SELECT
  mb.order_month,
  mb.order_year,
  mb.month_number,
  mb.month_name,
  mb.total_orders,
  mb.total_items_sold,
  mb.gross_revenue,
  mb.total_refunds,
  mb.net_revenue,
  LAG(mb.net_revenue) OVER (ORDER BY mb.order_month)       AS prev_month_net_revenue,
  mb.net_revenue
    - LAG(mb.net_revenue) OVER (ORDER BY mb.order_month)   AS mom_revenue_diff,
  ROUND(
    SAFE_DIVIDE(
      mb.net_revenue - LAG(mb.net_revenue) OVER (ORDER BY mb.order_month),
      LAG(mb.net_revenue) OVER (ORDER BY mb.order_month)
    ) * 100, 2
  )                                                         AS mom_revenue_pct,
  mb.total_customers,
  mb.new_customers,
  mb.avg_ticket,
  tc.category                                               AS top_category
FROM monthly_base AS mb
LEFT JOIN top_category_per_month AS tc
  ON mb.order_month = tc.order_month AND tc.rn = 1
ORDER BY mb.order_month;


-- ------------------------------------------------------------
-- trusted_customer_orders_summary
-- Granularidade: 1 linha por cliente
-- Uso: segmentação RFM, análise de churn, CRM
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.trusted_customer_orders_summary` AS
WITH valid_orders_revenue AS (
  SELECT
    vo.customer_id,
    vo.order_id,
    vo.order_date,
    ogr.gross_revenue,
    COALESCE(orr.total_refunded, 0) AS order_refund
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr
    ON vo.order_id = ogr.order_id
  LEFT JOIN `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS orr
    ON vo.order_id = orr.order_id
),
canceled_orders AS (
  SELECT
    customer_id,
    COUNT(*) AS total_canceled
  FROM `analytics-project-499319.ze_delivery_project.raw_orders`
  WHERE status = 'canceled'
  GROUP BY customer_id
),
fav_category AS (
  SELECT
    vo.customer_id,
    p.category,
    ROW_NUMBER() OVER (
      PARTITION BY vo.customer_id
      ORDER BY SUM(oi.quantity * oi.unit_price) DESC
    ) AS rn
  FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
    ON oi.order_id = vo.order_id
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_dim_products` AS p
    ON oi.product_id = p.product_id
  GROUP BY vo.customer_id, p.category
),
fav_payment AS (
  SELECT
    vo.customer_id,
    p.payment_method,
    ROW_NUMBER() OVER (
      PARTITION BY vo.customer_id
      ORDER BY COUNT(*) DESC
    ) AS rn
  FROM `analytics-project-499319.ze_delivery_project.raw_payments` AS p
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
    ON p.order_id = vo.order_id
  WHERE p.payment_status = 'captured'
  GROUP BY vo.customer_id, p.payment_method
),
customer_base AS (
  SELECT
    vor.customer_id,
    COUNT(DISTINCT vor.order_id)                                    AS total_valid_orders,
    MIN(vor.order_date)                                             AS first_order_date,
    MAX(vor.order_date)                                             AS last_order_date,
    DATE_DIFF(CURRENT_DATE(), MAX(vor.order_date), DAY)             AS days_since_last_order,
    SUM(vor.gross_revenue)                                          AS gross_revenue,
    SUM(vor.order_refund)                                           AS total_refunds,
    SUM(vor.gross_revenue) - SUM(vor.order_refund)                  AS net_revenue,
    ROUND(SUM(vor.gross_revenue) / COUNT(DISTINCT vor.order_id), 2) AS avg_ticket
  FROM valid_orders_revenue AS vor
  GROUP BY vor.customer_id
)
SELECT
  c.customer_id,
  c.customer_name,
  c.country,
  c.signup_date,
  COALESCE(cb.total_valid_orders, 0)   AS total_valid_orders,
  COALESCE(co.total_canceled, 0)       AS total_canceled_orders,
  ROUND(
    SAFE_DIVIDE(
      COALESCE(co.total_canceled, 0),
      COALESCE(cb.total_valid_orders, 0) + COALESCE(co.total_canceled, 0)
    ) * 100, 2
  )                                    AS cancel_rate,
  cb.first_order_date,
  cb.last_order_date,
  cb.days_since_last_order,
  DATE_DIFF(CURRENT_DATE(), c.signup_date, DAY) AS days_as_customer,
  COALESCE(cb.gross_revenue, 0)        AS gross_revenue,
  COALESCE(cb.total_refunds, 0)        AS total_refunds,
  COALESCE(cb.net_revenue, 0)          AS net_revenue,
  COALESCE(cb.avg_ticket, 0)           AS avg_ticket,
  fc.category                          AS favorite_category,
  fp.payment_method                    AS favorite_payment_method,
  cb.days_since_last_order             AS rfm_recency_days,
  COALESCE(cb.total_valid_orders, 0)   AS rfm_frequency,
  COALESCE(cb.net_revenue, 0)          AS rfm_monetary
FROM `analytics-project-499319.ze_delivery_project.raw_customers` AS c
LEFT JOIN customer_base   AS cb ON c.customer_id = cb.customer_id
LEFT JOIN canceled_orders AS co ON c.customer_id = co.customer_id
LEFT JOIN fav_category    AS fc ON c.customer_id = fc.customer_id AND fc.rn = 1
LEFT JOIN fav_payment     AS fp ON c.customer_id = fp.customer_id AND fp.rn = 1;


-- ------------------------------------------------------------
-- trusted_fact_orders
-- Granularidade: 1 linha por pedido válido
-- Uso: tabela base para qualquer slice analítico no BI
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW `analytics-project-499319.ze_delivery_project.trusted_fact_orders` AS
WITH first_purchase AS (
  SELECT
    customer_id,
    MIN(order_date) AS first_order_date
  FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders`
  GROUP BY customer_id
),
order_items_agg AS (
  SELECT
    oi.order_id,
    SUM(oi.quantity)              AS total_items,
    COUNT(DISTINCT oi.product_id) AS distinct_products
  FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
  INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
    ON oi.order_id = vo.order_id
  GROUP BY oi.order_id
),
primary_category_per_order AS (
  SELECT
    order_id,
    category,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY cat_revenue DESC
    ) AS rn
  FROM (
    SELECT
      oi.order_id,
      p.category,
      SUM(oi.quantity * oi.unit_price) AS cat_revenue
    FROM `analytics-project-499319.ze_delivery_project.raw_order_items` AS oi
    INNER JOIN `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
      ON oi.order_id = vo.order_id
    INNER JOIN `analytics-project-499319.ze_delivery_project.stg_dim_products` AS p
      ON oi.product_id = p.product_id
    GROUP BY oi.order_id, p.category
  )
),
payment_methods_per_order AS (
  SELECT
    order_id,
    STRING_AGG(DISTINCT payment_method ORDER BY payment_method) AS payment_methods
  FROM `analytics-project-499319.ze_delivery_project.raw_payments`
  WHERE payment_status = 'captured'
  GROUP BY order_id
)
SELECT
  vo.order_id,
  vo.customer_id,
  vo.order_date,
  FORMAT_DATE('%Y-%m',  vo.order_date)                        AS order_month,
  EXTRACT(YEAR FROM vo.order_date)                            AS order_year,
  FORMAT_DATE('%Y-W%V', vo.order_date)                        AS order_week,
  FORMAT_DATE('%A',     vo.order_date)                        AS day_of_week,
  c.customer_name,
  c.country,
  c.signup_date,
  (fp.first_order_date = vo.order_date)                       AS is_new_customer,
  vo.status                                                   AS order_status,
  COALESCE(oia.total_items, 0)                                AS total_items,
  COALESCE(oia.distinct_products, 0)                          AS distinct_products,
  pco.category                                                AS primary_category,
  pmo.payment_methods,
  (orr.total_refunded IS NOT NULL AND orr.total_refunded > 0) AS has_refund,
  ogr.gross_revenue,
  COALESCE(orr.total_refunded, 0)                             AS total_refunds,
  ogr.gross_revenue - COALESCE(orr.total_refunded, 0)         AS net_revenue,
  vo.total_captured
FROM `analytics-project-499319.ze_delivery_project.stg_valid_orders` AS vo
INNER JOIN `analytics-project-499319.ze_delivery_project.stg_order_gross_revenue` AS ogr
  ON vo.order_id = ogr.order_id
LEFT JOIN `analytics-project-499319.ze_delivery_project.raw_customers` AS c
  ON vo.customer_id = c.customer_id
LEFT JOIN first_purchase             AS fp  ON vo.customer_id = fp.customer_id
LEFT JOIN order_items_agg            AS oia ON vo.order_id    = oia.order_id
LEFT JOIN primary_category_per_order AS pco ON vo.order_id    = pco.order_id AND pco.rn = 1
LEFT JOIN payment_methods_per_order  AS pmo ON vo.order_id    = pmo.order_id
LEFT JOIN `analytics-project-499319.ze_delivery_project.stg_order_refunds` AS orr
  ON vo.order_id = orr.order_id
ORDER BY vo.order_date;
