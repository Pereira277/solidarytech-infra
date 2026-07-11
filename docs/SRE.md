# SRE.md — SolidaryTech: Confiabilidade do donation-service

> Documento formal de SRE — Frente 1 do Hackathon POSTECH Fase 5 (DCLT).
> Responsável técnico: Lucas Pereira — Turma POSTECH 2026.

---

## 1. Contexto: Por Que o donation-service É o Hot Path

### 1.1 Papel na Plataforma

O `donation-service` é o único ponto de processamento de doações financeiras da SolidaryTech.
Toda receita das ONGs parceiras passa obrigatoriamente por ele — sem ele, nenhuma doação
chega ao destino. Por isso é classificado como **Hot Path**: o caminho de negócio que não
pode falhar.

| Característica | Impacto em caso de falha |
|---|---|
| Processamento de doações em tempo real | Doação não registrada — receita perdida para a ONG |
| Integração com AWS SQS (eventos assíncronos) | Falha se propaga: downstream não recebe notificação de doação aprovada |
| Banco PostgreSQL como fonte de verdade | Dados de doação inacessíveis — relatórios e transparência comprometidos |
| Pico em campanhas (natal, black friday solidária) | Volume 10× maior — qualquer degradação é amplificada |

### 1.2 Endpoints e Criticidade

| Endpoint | Criticidade | SLO aplicável | Impacto de falha |
|---|---|---|---|
| `POST /donations` | **CRÍTICO** | SLO 1 + SLO 2 | Doação não processada, receita perdida |
| `GET /donations` | Normal | Monitorado, sem SLO formal | Usuário não vê histórico; sem impacto financeiro |
| `GET /health` | Infraestrutura | Liveness/Readiness probe do EKS | Pod removido do pool se unhealthy |

---

## 2. SLIs — Service Level Indicators

### SLI 1 — Latência (P99)

**Definição formal:**
> Percentil 99 do tempo de resposta HTTP das requisições `POST /donations`, medido
> do recebimento da requisição até o envio da resposta, em janela deslizante de 5 minutos.
> Chamadas ao SQS são assíncronas e não entram no cálculo.

**Por que P99:** captura a experiência do 1% de usuários mais lentos sem ser distorcido
por outliers extremos. Latências acima de 500ms em transações financeiras aumentam
significativamente o abandono de operação.

**Query PromQL (medição):**
```promql
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{
    job=~".*donation.*",
    handler="/donations",
    method="POST"
  }[5m])) by (le)
) * 1000
```

**Unidade:** milissegundos (ms)

---

### SLI 2 — Taxa de Erros 5xx

**Definição formal:**
> Proporção de requisições HTTP ao `donation-service` que retornam código de status
> 5xx (erros de servidor) em relação ao total de requisições, em janela deslizante
> de 5 minutos.

**Por que 5xx e não todos os erros:** Erros 4xx (Bad Request, Not Found) são falhas
do cliente e não refletem problemas no servidor. Incluí-los no SLI mascararia a
disponibilidade real do serviço. Apenas 5xx representa falha interna
(banco indisponível, SQS inacessível, panic no runtime Go).

**Query PromQL (medição):**
```promql
sum(rate(http_requests_total{
  job=~".*donation.*",
  status=~"5.."
}[5m]))
/
sum(rate(http_requests_total{
  job=~".*donation.*"
}[5m]))
* 100
```

**Unidade:** porcentagem (%)

---

## 3. SLOs — Service Level Objectives

### SLO 1 — Latência P99

| Atributo | Valor |
|---|---|
| **SLI medido** | Percentil 99 da latência de `POST /donations` |
| **Objetivo** | P99 < 500 ms em ≥ 99,5% dos intervalos de medição de 5 minutos |
| **Janela** | Rolling 30 dias |
| **Exclusão** | Indisponibilidade dentro da janela de manutenção programada (seção 4.2) |

**Fórmula de conformidade:**
```
(nº de intervalos de 5min com P99 < 500ms) / (total de intervalos) ≥ 99,5%
```

**Alerta disparado quando:** P99 > 500ms por mais de 2 minutos consecutivos.

---

### SLO 2 — Disponibilidade (Taxa de Erros)

| Atributo | Valor |
|---|---|
| **SLI medido** | Taxa de requisições com status 5xx |
| **Objetivo** | ≤ 0,1% de erros 5xx em janela de 30 dias |
| **Equivalente** | ≥ 99,9% das requisições resultam em 2xx ou 4xx |
| **Janela** | Rolling 30 dias |

**Fórmula de conformidade:**
```
(requisições 2xx + 4xx) / (total de requisições) ≥ 99,9%
```

**Alerta disparado quando:** Taxa de erros 5xx > 0,1% por mais de 2 minutos consecutivos.

---

## 4. SLA — Service Level Agreement

### 4.1 Compromisso com as ONGs Parceiras

| Métrica | Compromisso |
|---|---|
| **Disponibilidade mensal mínima** | 99,5% (≤ 3h36min de indisponibilidade/mês) |
| **Latência máxima P99** | < 500ms em 99,5% das requisições de doação |
| **Cobertura** | 24×7, incluindo finais de semana e feriados nacionais |
| **Canal de status** | Página de status atualizada em tempo real durante incidentes |

### 4.2 Janela de Manutenção Programada

**Horário:** Sábados, das 02h00 às 04h00 (UTC)

Justificativa: análise histórica mostra que este é o período de menor volume de doações
(menos de 2% do tráfego semanal). Indisponibilidade nessa janela **não conta** para o
cálculo mensal do SLO.

Requisitos:
- Comunicação mínima de 72 horas de antecedência por e-mail às ONGs cadastradas
- Duração máxima de 2 horas; se exceder, tratar como incidente não planejado
- Post em canal público de comunicação ao início e ao fim da manutenção

### 4.3 Penalidades por Violação de SLA

| Violação | Penalidade |
|---|---|
| Disponibilidade < 99,5% no mês | Notificação formal às ONGs afetadas + postmortem publicado em 48h |
| Violação recorrente (2× em 3 meses) | Auditoria de confiabilidade + plano de ação com prazo de 30 dias |
| Incidente com impacto financeiro comprovado | Relatório de causa-raiz público + medidas preventivas documentadas |

> O SLA não prevê compensação financeira dado o caráter sem fins lucrativos da SolidaryTech.
> O compromisso é de **transparência, comunicação e melhoria contínua**.

---

## 5. Error Budget

### 5.1 Cálculo do Budget Mensal

| Parâmetro | Valor |
|---|---|
| Janela de medição | 30 dias = 43.200 minutos |
| Taxa de erro máxima (SLO 2) | 0,1% |
| **Error Budget total** | 43.200 × 0,001 = **43,2 minutos/mês** de falha tolerada |
| Equivalente em requisições (100 req/min) | ~4.320 requisições com erro por mês |

### 5.2 Política de Congelamento de Deploys

| Condição | Ação obrigatória |
|---|---|
| ≥ 50% do budget consumido em < 15 dias (> 21,6 min) | **Congelar todos os deploys** — acionar revisão de confiabilidade |
| ≥ 75% do budget consumido | Congelar deploys + war room + plano de mitigação em 4 horas |
| 100% do budget consumido | SLO violado → postmortem obrigatório + bloqueio de novos features até aprovação do SRE |

**Quem aciona o congelamento:** alerta `DonationErrorBudgetBurn` do Alertmanager notifica
o tech lead automaticamente; a policy de congelamento é aplicada pelo pipeline CI/CD.

**Quem libera:** revisão do postmortem aprovada pelo SRE responsável, com evidência de
resolução da causa-raiz.

### 5.3 Query PromQL — Error Budget Restante (%)

```promql
(
  0.001
  - clamp_min(
      sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[30d]))
      / sum(rate(http_requests_total{job=~".*donation.*"}[30d])),
      0
    )
) / 0.001 * 100
```

---

## 6. Queries PromQL — Referência Completa

> **Pré-requisito de instrumentação:** As queries abaixo assumem que o `donation-service`
> expõe métricas no padrão Prometheus (`http_requests_total` com labels `status`, `method`,
> `handler`; e `http_request_duration_seconds` histogram), via `prometheus/client_golang`,
> com scraping configurado por ServiceMonitor do kube-prometheus-stack.
>
> Alternativa: configurar o OTel Collector com exporter `prometheusremotewrite` apontando
> para `http://prometheus-operated.monitoring.svc.cluster.local:9090/api/v1/write`
> para que as métricas OTLP do serviço também cheguem ao Prometheus.

### 6.1 Taxa de Erros 5xx (real-time, janela 5min)

```promql
sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[5m]))
/ sum(rate(http_requests_total{job=~".*donation.*"}[5m]))
* 100
```

### 6.2 Latência P99 / P95 / P50 em ms (janela 5min)

```promql
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{job=~".*donation.*"}[5m])) by (le)
) * 1000
```

### 6.3 Disponibilidade calculada (janela 30 dias)

```promql
(
  1
  - sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[30d]))
    / sum(rate(http_requests_total{job=~".*donation.*"}[30d]))
) * 100
```

### 6.4 Error Budget restante (%) — janela 30 dias

```promql
(
  0.001
  - clamp_min(
      sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[30d]))
      / sum(rate(http_requests_total{job=~".*donation.*"}[30d])),
      0
    )
) / 0.001 * 100
```

### 6.5 Throughput (req/s)

```promql
sum(rate(http_requests_total{job=~".*donation.*"}[5m]))
```

### 6.6 Disponibilidade por pod — proxy kube-state-metrics (sem ServiceMonitor)

```promql
kube_deployment_status_replicas_available{
  namespace="solidarytech",
  deployment="donation-service"
}
/ kube_deployment_spec_replicas{
  namespace="solidarytech",
  deployment="donation-service"
} * 100
```

---

## 7. Redução de MTTR com a Stack de Observabilidade

### 7.1 Definição de MTTR no Contexto SolidaryTech

```
MTTR = TTD + TTN + TTDiag + TTM

TTD    — Time to Detect    (detecção automática do incidente)
TTN    — Time to Notify    (notificação do time de plantão)
TTDiag — Time to Diagnose  (identificação da causa-raiz)
TTM    — Time to Mitigate  (rollback ou hotfix aplicado)
```

### 7.2 Metas e Ferramentas por Fase

| Fase | Ferramenta | Meta | Mecanismo |
|---|---|---|---|
| **Detecção (TTD)** | Prometheus Alertmanager | < 5 min | Alertas com `for: 2m`; avaliação a cada 1 min |
| **Notificação (TTN)** | Alertmanager → e-mail/Slack | < 2 min | Roteamento automático por severidade |
| **Diagnóstico (TTDiag)** | Grafana + Loki + New Relic | < 10 min | Dashboard SRE + filtro de logs por pod + trace distribuído |
| **Mitigação (TTM)** | ArgoCD rollback | < 5 min | `argocd app rollback donation-service` em 1 comando |

**MTTR alvo total: < 22 minutos**

### 7.3 Comparativo — Antes e Depois da Observabilidade

| Fase | Sem observabilidade (baseline) | Com stack SolidaryTech | Melhoria |
|---|---|---|---|
| Detecção | ~60 min (relato de usuário) | < 5 min (alerta automático) | **-91%** |
| Notificação | Manual (~15 min) | < 2 min (automático) | **-87%** |
| Diagnóstico | ~2h (grep distribuído) | < 10 min (Grafana + Loki + New Relic) | **-92%** |
| Mitigação | ~1h (redeploy manual) | < 5 min (ArgoCD rollback) | **-92%** |
| **MTTR total** | **~4 horas** | **< 22 minutos** | **~91% de redução** |

### 7.4 Como Cada Ferramenta Contribui

**Prometheus + Alertmanager:** dispara antes que usuários reportem; elimina a detecção
reativa por relato.

**Grafana SRE Dashboard:** mostra em uma tela qual SLI está violado, desde quando e com
qual magnitude — elimina a fase de coleta manual de evidências.

**Loki + Promtail:** filtra logs de todos os pods com query por pod e timerange, sem SSH
em servidores. Correlacionar spike de erros com mensagens de log leva minutos.

**New Relic APM (via OTel):** mostra a árvore de spans da requisição com erro — qual
chamada ao RDS excedeu o timeout, qual mensagem SQS não foi entregue.

**ArgoCD:** mantém histórico de todos os syncs com hash do commit; rollback para versão
anterior é determinístico e leva menos de 5 minutos.

### 7.5 Regras de Alerta Prometheus (PrometheusRule recomendado)

```yaml
groups:
  - name: donation-service-slo
    rules:
      - alert: DonationErrorRateHigh
        expr: |
          sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[5m]))
          / sum(rate(http_requests_total{job=~".*donation.*"}[5m])) > 0.001
        for: 2m
        labels:
          severity: critical
          service: donation-service
        annotations:
          summary: "SLO VIOLADO — taxa de erros 5xx > 0,1%"
          description: "Taxa atual: {{ $value | humanizePercentage }}. SLO: 0,1%."

      - alert: DonationLatencyHigh
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket{job=~".*donation.*"}[5m])) by (le)
          ) * 1000 > 500
        for: 2m
        labels:
          severity: warning
          service: donation-service
        annotations:
          summary: "SLO WARNING — latência P99 > 500ms"
          description: "P99 atual: {{ $value | humanize }}ms. SLO: 500ms."

      - alert: DonationErrorBudgetBurn
        expr: |
          (
            0.001 - clamp_min(
              sum(rate(http_requests_total{job=~".*donation.*",status=~"5.."}[6h]))
              / sum(rate(http_requests_total{job=~".*donation.*"}[6h])), 0
            )
          ) / 0.001 < 0.50
        for: 5m
        labels:
          severity: warning
          service: donation-service
        annotations:
          summary: "ERROR BUDGET — > 50% do budget consumido"
          description: "Budget restante: {{ $value | humanizePercentage }}. Congelar deploys."
```
