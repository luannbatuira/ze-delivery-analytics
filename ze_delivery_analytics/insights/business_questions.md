# 📊 Questões de Negócio — Respostas e Insights

Análise realizada sobre dados de Janeiro a Abril de 2026.
Todas as métricas consideram apenas **pedidos válidos** (`status <> 'canceled'` com pagamento `captured`).

---

## Q1 — Qual foi a receita líquida por mês?

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_q1_net_revenue_by_month`;
```

### Resultado

| Mês | Receita Bruta | Reembolsos | Receita Líquida |
|---|---|---|---|
| 2026-01 | R$ 610,00 | R$ 0,00 | **R$ 610,00** |
| 2026-02 | R$ 1.090,00 | R$ 100,00 | **R$ 990,00** |
| 2026-03 | R$ 1.635,00 | R$ 260,00 | **R$ 1.375,00** |
| 2026-04 | R$ 1.195,00 | R$ 45,00 | **R$ 1.150,00** |
| **Total** | **R$ 4.530,00** | **R$ 405,00** | **R$ 4.125,00** |

### Insights
- Crescimento consistente de Janeiro (+62,3%) a Março, com leve retração em Abril (-16,4%).
- Março foi o mês de maior receita líquida (R$ 1.375), impulsionado por 4 pedidos incluindo um de R$ 1.030 (Monitor + Mouse).
- Fevereiro registrou o maior impacto de reembolso relativo: R$ 100 de volta sobre R$ 1.090 brutos (9,2%).
- Janeiro teve zero reembolsos — todos os pedidos foram entregues sem contestação.
- A queda em Abril pode refletir sazonalidade ou base de comparação alta de Março, não necessariamente um problema estrutural.

---

## Q2 — Quantos clientes fizeram a primeira compra válida em cada mês?

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_q2_new_customers_by_month`;
```

### Resultado

| Mês | Novos Clientes |
|---|---|
| 2026-01 | 2 |
| 2026-02 | 1 |
| 2026-03 | 3 |
| 2026-04 | 2 |
| **Total** | **8** |

### Insights
- 8 dos 12 clientes cadastrados realizaram ao menos uma compra válida no período — taxa de conversão de cadastro para compra de **66,7%**.
- Março foi o melhor mês de aquisição (3 novos compradores), coincidindo com o pico de receita.
- Fevereiro foi o mês mais fraco em aquisição (1 novo cliente), mesmo com receita bruta de R$ 1.090 — sinal de que clientes recorrentes sustentaram o resultado.
- 4 clientes cadastrados nunca realizaram uma compra válida no período analisado — oportunidade de ativação.

---

## Q3 — Qual categoria teve maior receita bruta em pedidos válidos?

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_q3_gross_revenue_by_category`;
```

### Resultado

| Categoria | Receita Bruta | Participação |
|---|---|---|
| 🥇 Monitores | R$ 1.780,00 | 39,3% |
| Periféricos | R$ 1.370,00 | 30,2% |
| Acessórios | R$ 540,00 | 11,9% |
| Escritório | R$ 540,00 | 11,9% |
| Sem Categoria | R$ 300,00 | 6,6% |
| **Total** | **R$ 4.530,00** | **100%** |

### Insights
- **Monitores** lidera com 39,3% da receita bruta, concentrada em apenas 2 pedidos com o produto Monitor 24in (R$ 890/un) — alta dependência de SKU único.
- **Periféricos** é a categoria mais diversificada: Keyboard, Mouse e Webcam, representando 30,2% da receita.
- Acessórios e Escritório empatam em R$ 540 cada — ambas com produtos de ticket menor e maior volume de itens.
- **"Sem Categoria"** representa R$ 300 referente ao Gift Card (PRD006), produto com categoria ausente no cadastro — problema de qualidade de dados que distorce análises de mix.
- Recomendação: classificar o Gift Card em uma categoria adequada (ex: `Vouchers`) e criar alerta para novos produtos sem categoria.

---

## Q4 — Qual foi o ticket médio de pedidos válidos?

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_q4_avg_ticket`;
```

### Resultado

| Pedidos Válidos | Receita Bruta Total | Ticket Médio |
|---|---|---|
| 12 | R$ 4.530,00 | **R$ 377,50** |

### Insights
- Ticket médio de R$ 377,50 é elevado para e-commerce de itens de escritório/tech — reflexo da presença de produtos de alto valor (Monitor R$ 890, Webcam R$ 320).
- Variação expressiva entre pedidos: mínimo de R$ 120 (USB-C Cable) e máximo de R$ 1.030 (Monitor + Mouse) — alta dispersão que o ticket médio sozinho não captura.
- Recomendação: acompanhar também mediana e distribuição por faixa de valor para entender melhor o comportamento de compra.

#### Ticket médio por mês (via trusted_monthly_revenue)

| Mês | Ticket Médio |
|---|---|
| 2026-01 | R$ 305,00 |
| 2026-02 | R$ 545,00 |
| 2026-03 | R$ 408,75 |
| 2026-04 | R$ 298,75 |

Fevereiro teve o maior ticket médio (R$ 545) puxado pelo pedido de Monitor de R$ 890.

---

## Q5 — Quais problemas de qualidade foram encontrados nos dados?

### 5a. Pagamentos captured duplicados

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_duplicate_payments`;
```

**Pedido O1009**: dois pagamentos `captured` de R$ 120,00 no mesmo dia via PIX.
Possível duplicata de transação — se confirmado, a receita deste pedido está inflada em R$ 120.

---

### 5b. Pedidos com múltiplos status de pagamento

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_mixed_payment_status`;
```

**Pedido O1008**: dois `captured` (R$ 600 + R$ 430) — tratado como parcelamento.
**Pedido O1012**: `authorized` + `captured` — o `authorized` (PAY014) é ignorado na staging, apenas o `captured` (PAY015) é considerado.

---

### 5c. Produtos sem categoria

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_products_no_category`;
```

**PRD006 — Gift Card**: categoria `NULL` no cadastro.
Tratado na `stg_dim_products` como `'Sem Categoria'`, mas distorce análises de mix de produto.
**Ação recomendada**: classificar como `Vouchers` ou categoria equivalente.

---

### 5d. Divergência entre preço de venda e preço de lista

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_price_divergence`;
```

**OI020 — Keyboard (PRD003)** no pedido O1014: vendido a R$ 250,00 vs `list_price` de R$ 260,00.
Diferença de R$ 10,00 — possível desconto aplicado sem registro formal.
**Ação recomendada**: criar campo `discount_amount` na tabela de itens para rastrear descontos explicitamente.

---

### 5e. Pedidos cancelados com pagamento captured

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_canceled_with_capture`;
```

**Pedido O1005**: status `canceled` mas com pagamento `captured` de R$ 320,00.
Indica que o pagamento foi capturado antes do cancelamento — deveria ter gerado reembolso (e de fato gerou: R003).
Sequência correta, mas o status do pagamento deveria ser atualizado para `refunded`.

---

### 5f. Reembolsos em pedidos cancelados

```sql
SELECT * FROM `analytics-project-499319.ze_delivery_project.stg_dq_refunds_on_canceled`;
```

**R003** referencia O1005 (cancelado) com motivo `canceled_order`.
Tecnicamente correto como operação financeira, mas cria ambiguidade: pedidos cancelados com reembolso vs. pedidos entregues com reembolso devem ser tratados separadamente nas análises.

---

### Resumo dos Problemas de Qualidade

| # | Severidade | Tabela | Problema | Status |
|---|---|---|---|---|
| 1 | 🔴 Alta | `raw_payments` | Possível duplicata de pagamento PIX em O1009 | Investigar com time financeiro |
| 2 | 🟡 Média | `raw_payments` | O1012 com `authorized` + `captured` | Tratado na staging |
| 3 | 🟡 Média | `raw_products` | PRD006 sem categoria | Tratado na staging como 'Sem Categoria' |
| 4 | 🟡 Média | `raw_order_items` | Desconto não documentado em OI020 | Criar campo discount_amount |
| 5 | 🟢 Baixa | `raw_payments` | Status de pagamento não atualizado após cancelamento O1005 | Processo operacional |
| 6 | 🟢 Baixa | `raw_refunds` | Reembolso registrado em pedido cancelado (R003) | Redundância aceitável |
