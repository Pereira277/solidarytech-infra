# New Relic — Applied Intelligence e Política de Alertas do donation-service

> Guia operacional de configuração. Documentação, não manifesto Kubernetes — não é
> aplicado via `kubectl`/ArgoCD. Complementa `docs/ITSM.md`, seção 2.

---

## 1. Pré-requisito

O License Key do New Relic já está configurado no cluster via secret `new-relic-secret`
(namespace `monitoring`) e os traces do `donation-service`, `ngo-service` e
`volunteer-service` já chegam via OTel Collector (ver `docs/RUNBOOK.md`, seção 11). Os
passos abaixo assumem que os 3 serviços já aparecem em **APM & Services** no New Relic.

---

## 2. Ativar Applied Intelligence no New Relic UI

1. Acesse [https://one.newrelic.com](https://one.newrelic.com)
2. No menu lateral, navegue até **Alerts** → **Applied Intelligence**
3. Na aba **Settings**, confirme que a **incident correlation** está habilitada (é o
   comportamento padrão em contas New Relic com Applied Intelligence disponível)
4. Em **Applied Intelligence** → **Anomalies**, o New Relic começa a construir a baseline
   de comportamento automaticamente assim que houver dados de APM suficientes (recomendado:
   aguardar pelo menos algumas horas de tráfego real ou simulado antes de avaliar a
   qualidade da detecção)

---

## 3. Criar política de alertas para o donation-service

### 3.1 Criar a política (Alert Policy)

1. **Alerts** → **Policies** → **New alert policy**
2. Nome: `donation-service-critical-path`
3. Incident preference: **By condition and signal** (evita que múltiplas condições do
   mesmo serviço gerem incidents separados desnecessariamente)

### 3.2 Criar as condições (Alert Conditions)

Para cada linha da tabela abaixo, **Alerts** → **Policies** → `donation-service-critical-path`
→ **New alert condition** → tipo **NRQL condition**:

| Nome da condição | NRQL (exemplo) | Limiar Warning | Limiar Critical |
|---|---|---|---|
| `donation-p99-latency` | `SELECT percentile(duration, 99) FROM Transaction WHERE appName = 'donation-service' AND name LIKE '%/donations%'` | > 0.4 (400ms) por 5 min | > 0.5 (500ms) por 2 min |
| `donation-error-rate` | `SELECT percentage(count(*), WHERE error IS true) FROM Transaction WHERE appName = 'donation-service'` | > 0.05% | > 0.1% |
| `donation-pod-unavailable` | `SELECT count(*) FROM Metric WHERE metricName = 'kube_deployment_status_replicas_available' AND deployment = 'donation-service'` (via integração Prometheus remote-write, se configurada) | — | = 0 por 1 min |

> Os valores de threshold replicam exatamente a política sugerida em `docs/ITSM.md`,
> seção 2.4, que por sua vez replica o SLO formal de `docs/SRE.md`, seção 2. Não alterar
> os limiares aqui sem atualizar os dois documentos.

Para cada condição, configurar:
- **Signal**: janela de agregação de 1 minuto, evaluation offset padrão
- **Threshold**: usar os pares Warning/Critical da tabela acima como duas thresholds na
  mesma condição (New Relic permite múltiplos níveis de severidade por condição NRQL)
- **Duration**: "for at least" conforme a coluna de duração da tabela

### 3.3 Configurar canais de notificação

1. **Alerts** → **Notifications** → **New destination**
2. Criar destinos para:
   - **Slack** (`#incidents` para Critical, `#alerts` para Warning) — webhook URL do
     workspace da SolidaryTech
   - **Email** — lista do time técnico
   - **PagerDuty** (opcional, apenas para P1 conforme `docs/ITSM.md` seção 5) — integration
     key do serviço PagerDuty correspondente
3. Associar os destinos à política `donation-service-critical-path` em **Workflows**,
   filtrando por severidade (`priority = critical` → PagerDuty + Slack `#incidents`;
   `priority = warning` → Slack `#alerts`)

---

## 4. Configurar anomaly detection baseline

1. **Alerts** → **Applied Intelligence** → **Anomalies**
2. Verificar que `donation-service` aparece na lista de entidades monitoradas (aparece
   automaticamente após dados suficientes de APM)
3. Em **Proactive Detection** (se disponível no plano da conta), habilitar detecção
   comportamental para as métricas de latência e taxa de erro do `donation-service` — isso
   ativa a baseline adaptativa mencionada em `docs/ITSM.md`, seção 2.1, complementar às
   condições NRQL de limiar fixo criadas na Seção 3.2 acima
4. Revisar periodicamente **Applied Intelligence** → **Incidents** para confirmar que
   alertas relacionados ao mesmo evento estão sendo corretamente correlacionados em um
   único incident, não notificados separadamente (reduz ruído — ver `docs/ITSM.md`,
   seção 2.2)

---

## 5. Validação

Após configurar a política, confirmar:

```
Alerts → Policies → donation-service-critical-path
  → 3 condições ativas (latência, erro, disponibilidade de pod)
  → Notification workflows associados por severidade

Alerts → Applied Intelligence → Anomalies
  → donation-service listado como entidade monitorada
```

Testar a política disparando um alerta manualmente (ex.: escalar réplicas do
`donation-service` para 0 momentaneamente em ambiente de teste) e confirmar que a
notificação chega ao canal esperado dentro da meta de MTTA (< 5 minutos, `docs/ITSM.md`
seção 7).
