# 📦 Zé Delivery — Analytics Engineering Case

Solução de Analytics Engineering desenvolvida como case técnico para a posição de Analytics Engineer Jr. na Zé Delivery.

---

## 🗂️ Estrutura do Repositório

```
ze_delivery_analytics/
│
├── queries/
│   ├── raw/
│   │   ├── ddl_raw_tables.sql        # CREATE TABLE das tabelas brutas
│   │   └── load_raw_bq.sh            # Script de carga via bq load (gcloud CLI)
│   │
│   ├── staging/
│   │   └── ddl_staging_views.sql     # Views de limpeza, regras de negócio e DQ
│   │
│   └── trusted/
│       └── ddl_trusted_views.sql     # Views analíticas prontas para consumo
│
├── insights/
│   └── business_questions.md         # Respostas às 5 questões de negócio
│
└── README.md
```

---

## 🏗️ Arquitetura da Solução

```
CSVs (fonte)
     │
     ▼
 raw_*          → Tabelas brutas: espelho fiel dos arquivos originais
     │
     ▼
 stg_*          → Views de staging: limpeza, regras de negócio e DQ
     │
     ▼
 trusted_*      → Views analíticas: grãos consolidados prontos para BI
```

Todas as camadas vivem no mesmo dataset BigQuery:
```
analytics-project-499319.ze_delivery_project
```

---

## 📐 Modelo de Dados

```
raw_customers ──< raw_orders ──< raw_order_items >── raw_products
                      │
                      ├──< raw_payments
                      └──< raw_refunds
```

| Tabela | Descrição | Linhas |
|---|---|---|
| `raw_customers` | Cadastro de clientes | 12 |
| `raw_products` | Catálogo de produtos | 8 |
| `raw_orders` | Pedidos realizados | 14 |
| `raw_order_items` | Itens por pedido | 20 |
| `raw_payments` | Pagamentos por pedido | 17 |
| `raw_refunds` | Reembolsos por pedido | 4 |

---

## 📌 Premissas e Regras de Negócio

### Definição de Pedido Válido
> `status <> 'canceled'` **E** ao menos um pagamento com `payment_status = 'captured'`

Essa é a regra central da solução. Todos os cálculos de receita, ticket médio, novos clientes e categoria partem exclusivamente de pedidos válidos.

### Regras adotadas

| Decisão | Critério adotado | Motivo |
|---|---|---|
| Pedidos com múltiplos `captured` | Somar todos os valores | Tratado como parcelamento (ex: O1008 com R$600 + R$430) |
| Pagamentos `authorized` | Ignorados | Não representam receita confirmada |
| Pagamentos `failed` | Ignorados | Transação não concluída |
| Reembolsos | Atribuídos ao mês do pedido | Consistência temporal — o pedido pertence ao mês em que ocorreu |
| Produto sem categoria (PRD006) | `'Sem Categoria'` | Normalização para não perder a linha nas análises de mix |
| `unit_price` vs `list_price` | Usado `unit_price` | É o preço efetivamente praticado na venda |

---

## ⚠️ Granularidade e Risco de Duplicidade

A principal fonte de duplicidade neste modelo é a tabela `raw_payments` — um pedido pode ter múltiplos registros de pagamento com status diferentes (`captured`, `authorized`, `failed`).

**Como foi resolvido:**

A view `stg_payments_captured` agrega `SUM(amount)` filtrando apenas `payment_status = 'captured'` **antes** de qualquer JOIN com pedidos. Isso garante que o JOIN posterior em `stg_valid_orders` seja 1:1 (um valor por pedido), eliminando o risco de fanout de linhas e receita inflada.

```sql
-- stg_payments_captured: 1 linha por pedido, apenas captured
SELECT order_id, SUM(amount) AS total_captured
FROM raw_payments
WHERE payment_status = 'captured'
GROUP BY order_id
```

O INNER JOIN (não LEFT JOIN) em `stg_valid_orders` é intencional: garante que só entrem pedidos com pagamento confirmado, sem necessidade de filtro adicional nas camadas superiores.

---

## 🔄 Tradeoffs e Decisões de Arquitetura

| Decisão | O que foi feito | Tradeoff |
|---|---|---|
| Views vs tabelas materializadas | Todas as camadas como views | Free tier do BQ não permite DML. Em produção, `trusted_*` seriam tabelas particionadas por `order_date` para melhor performance |
| Dataset único | Tudo em `ze_delivery_project` | Simplicidade para o case. Em produção, separaria em `raw`, `staging` e `trusted` para controle de acesso por camada |
| Carga via `bq load` | Script shell com gcloud CLI | Alternativa ao INSERT (bloqueado no free tier). Em produção, usaria pipeline incremental via Airflow ou dbt + Cloud Composer |
| Sem testes automatizados | Validação manual com SELECT | Com mais tempo, implementaria testes de unicidade, not-null e range via dbt test |

---

## 🚀 O Que Faria com Mais Tempo

**1. Investigar a duplicata de pagamento no O1009**
Dois `captured` de R$120 via PIX no mesmo dia — alta probabilidade de duplicata. Acionaria o time financeiro para confirmar e, se confirmado, corrigiria a receita líquida de Março em -R$120.

**2. Testes de qualidade automatizados**
Implementaria testes estilo dbt para cada tabela:
- Unicidade de `order_id` em `stg_valid_orders`
- Not-null em `gross_revenue` e `order_date`
- Range check: `unit_price > 0`, `amount > 0`
- Referential integrity: todo `order_id` em `order_items` existe em `orders`

**3. Materializar a camada Trusted**
Converter as views `trusted_*` em tabelas particionadas por `order_date` e clusterizadas por `order_month` e `country`, reduzindo custo e latência de consulta no BI.

**4. Pipeline incremental**
Substituir a carga full (`--replace`) por carga incremental baseada em `order_date`, processando apenas novos registros a cada execução.

**5. Classificar o Gift Card**
Criar categoria `Vouchers` para o PRD006 e adicionar alerta automático para novos produtos sem categoria antes de entrar em produção.

---

## 🧱 Etapas do Desenvolvimento

### Etapa 1 — Entendimento dos Dados

O primeiro passo foi explorar os 6 arquivos CSV para entender o modelo de dados, identificar relacionamentos entre tabelas e mapear problemas de qualidade antes de escrever qualquer query.

Problemas identificados ainda nessa etapa:
- `PRD006` (Gift Card) sem categoria no cadastro de produtos
- Pedido `O1008` com dois pagamentos `captured` — parcelamento ou duplicata?
- Pedido `O1009` com dois `captured` idênticos no mesmo dia — suspeita de duplicata
- `OI020`: Keyboard vendido a R$ 250 com `list_price` de R$ 260
- `O1005`: cancelado mas com pagamento `captured` e reembolso registrado

---

### Etapa 2 — Definição de Pedido Válido

Antes de qualquer cálculo, foi necessário alinhar a definição de negócio:

> **Pedido válido** = `status <> 'canceled'` **E** possui ao menos um pagamento com `payment_status = 'captured'`

Essa regra exclui:
- Pedidos cancelados (`O1005`, `O1010`)
- Pedidos sem captura de pagamento confirmada

Para pedidos com múltiplos `captured` (ex: `O1008`), a decisão foi **somar todos**, tratando como parcelamento.

---

### Etapa 3 — Camada RAW

Criação das 6 tabelas brutas no BigQuery, espelhando fielmente os CSVs sem nenhuma transformação. Os dados foram carregados via **`bq load`** (gcloud CLI) — alternativa ao DML `INSERT`, que não é permitido no free tier do BigQuery.

```bash
bq load --project_id="analytics-project-499319" \
  --replace --source_format=CSV --skip_leading_rows=1 \
  ze_delivery_project.raw_customers "customers 1.csv" \
  "customer_id:STRING,customer_name:STRING,signup_date:DATE,country:STRING"
```

---

### Etapa 4 — Camada STAGING

Views que aplicam as regras de negócio e centralizam a lógica de transformação. Divididas em três grupos:

**Base (dependências das demais):**
- `stg_dim_products` — normaliza categoria `NULL` → `'Sem Categoria'`
- `stg_payments_captured` — agrega apenas pagamentos `captured` por pedido
- `stg_valid_orders` — aplica a definição de pedido válido via INNER JOIN com pagamentos
- `stg_order_gross_revenue` — calcula receita bruta por pedido (`quantity × unit_price`)
- `stg_order_refunds` — agrega reembolsos por pedido

**Analíticas (respondem às questões de negócio):**
- `stg_q1_net_revenue_by_month` — receita líquida por mês
- `stg_q2_new_customers_by_month` — primeiros compradores por mês
- `stg_q3_gross_revenue_by_category` — receita bruta por categoria
- `stg_q4_avg_ticket` — ticket médio de pedidos válidos

**Data Quality (diagnóstico de problemas):**
- `stg_dq_duplicate_payments` — pagamentos captured duplicados
- `stg_dq_mixed_payment_status` — pedidos com múltiplos status de pagamento
- `stg_dq_products_no_category` — produtos sem categoria
- `stg_dq_price_divergence` — divergência entre preço de venda e preço de lista
- `stg_dq_canceled_with_capture` — pedidos cancelados com pagamento captured
- `stg_dq_refunds_on_canceled` — reembolsos em pedidos cancelados

---

### Etapa 5 — Camada TRUSTED

Views analíticas com grãos consolidados, prontas para conectar diretamente a ferramentas de BI (Looker, Power BI, Metabase) ou modelos de Data Science.

Inicialmente projetadas como tabelas materializadas com `PARTITION BY` e `CLUSTER BY`, foram convertidas para **views** por limitação do free tier do BigQuery, que não permite DML (`INSERT INTO`).

| View | Granularidade | Principais métricas |
|---|---|---|
| `trusted_daily_revenue` | 1 linha / dia | Receita bruta, líquida, reembolsos, novos clientes, ticket médio |
| `trusted_monthly_revenue` | 1 linha / mês | Tudo do diário + variação MoM (`mom_revenue_diff`, `mom_revenue_pct`) e categoria top |
| `trusted_customer_orders_summary` | 1 linha / cliente | RFM (recência, frequência, monetário), taxa de cancelamento, categoria e método favoritos |
| `trusted_fact_orders` | 1 linha / pedido válido | Todas as dimensões desnormalizadas — base para qualquer slice analítico |

---

### Etapa 6 — Validação dos Resultados

Após criar todas as views, as 4 questões analíticas foram validadas diretamente no BigQuery Studio consultando as `stg_q*`. Os resultados foram conferidos manualmente e estão documentados em [`insights/business_questions.md`](insights/business_questions.md).

As views `trusted_*` também foram validadas com `SELECT *`, confirmando consistência dos dados entre as camadas.

---

## ✅ Como Reproduzir

### Pré-requisitos
- Conta no [Google Cloud](https://console.cloud.google.com/) com projeto criado
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) instalado e autenticado
- Dataset criado:
```bash
bq mk --location=US analytics-project-499319:ze_delivery_project
```

### Passo a passo

**1. Criar tabelas RAW** — execute `queries/raw/ddl_raw_tables.sql` no BigQuery Studio

**2. Carregar os dados** — coloque os CSVs na mesma pasta do script e rode:
```bash
cd queries/raw
bash load_raw_bq.sh
```

**3. Criar views Staging** — execute `queries/staging/ddl_staging_views.sql` no BQ Studio, **um bloco `CREATE OR REPLACE VIEW` por vez**, na ordem em que aparecem no arquivo

**4. Criar views Trusted** — execute `queries/trusted/ddl_trusted_views.sql` da mesma forma

**5. Validar** — rode os `SELECT *` nas views `stg_q1` a `stg_q4` e nas `trusted_*`

---

## 📊 Views da Camada Staging

| View | Tipo | Descrição |
|---|---|---|
| `stg_dim_products` | Base | Produtos com categoria normalizada |
| `stg_payments_captured` | Base | Pagamentos captured agregados por pedido |
| `stg_valid_orders` | Base | Pedidos válidos conforme regra de negócio |
| `stg_order_gross_revenue` | Base | Receita bruta por pedido válido |
| `stg_order_refunds` | Base | Total de reembolsos por pedido |
| `stg_q1_net_revenue_by_month` | Analítica | Q1: Receita líquida por mês |
| `stg_q2_new_customers_by_month` | Analítica | Q2: Novos clientes por mês |
| `stg_q3_gross_revenue_by_category` | Analítica | Q3: Receita bruta por categoria |
| `stg_q4_avg_ticket` | Analítica | Q4: Ticket médio de pedidos válidos |
| `stg_dq_duplicate_payments` | DQ | Pagamentos possivelmente duplicados |
| `stg_dq_mixed_payment_status` | DQ | Pedidos com múltiplos status de pagamento |
| `stg_dq_products_no_category` | DQ | Produtos sem categoria |
| `stg_dq_price_divergence` | DQ | Divergência entre unit_price e list_price |
| `stg_dq_canceled_with_capture` | DQ | Pedidos cancelados com pagamento captured |
| `stg_dq_refunds_on_canceled` | DQ | Reembolsos em pedidos cancelados |

---

## 📈 Views da Camada Trusted

| View | Granularidade | Uso |
|---|---|---|
| `trusted_daily_revenue` | 1 linha / dia | Gráficos diários, detecção de anomalias |
| `trusted_monthly_revenue` | 1 linha / mês | Relatórios executivos, variação MoM |
| `trusted_customer_orders_summary` | 1 linha / cliente | Segmentação RFM, churn, CRM |
| `trusted_fact_orders` | 1 linha / pedido | Base para qualquer análise no BI |

---

## 🔍 Questões de Negócio

As respostas detalhadas com queries e resultados estão em [`insights/business_questions.md`](insights/business_questions.md).

---

## 🛠️ Stack

- **BigQuery** (Google Cloud) — armazenamento e processamento
- **GoogleSQL** — linguagem de queries
- **gcloud CLI / bq CLI** — carga de dados
- **Git / GitHub** — versionamento
