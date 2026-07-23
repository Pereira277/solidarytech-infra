# ITSM.md — SolidaryTech: Gestão de Incidentes e AIOps

> Documento formal de ITSM/AIOps — Frente 3 do Hackathon POSTECH Fase 5 (DCLT).
> Responsável técnico: Lucas Pereira — Turma POSTECH 2026.

---

## 1. Visão Geral

A SolidaryTech adota AIOps (Artificial Intelligence for IT Operations) via **New Relic
Applied Intelligence** para detecção preditiva de incidentes no `donation-service` —
o Hot Path da plataforma (ver `docs/SRE.md`, seção 1). Em vez de depender exclusivamente
de limiares estáticos configurados manualmente, o Applied Intelligence aprende o
comportamento normal de latência, taxa de erro e throughput ao longo do tempo e sinaliza
desvios estatisticamente anômalos antes que cruzem os limiares fixos dos alertas
tradicionais.

**Por que isso importa para o negócio:** cada minuto de indisponibilidade do
`donation-service` é receita de ONGs parceiras não processada em tempo real. Detecção
preditiva reduz o tempo entre o início da degradação e a intervenção humana — o
componente TTD (Time to Detect) do MTTR definido em `docs/SRE.md`, seção 7 — encurtando
a janela de impacto antes que o problema afete um volume relevante de doadores.

**Como isso se conecta ao restante da stack:** o Applied Intelligence não substitui
Prometheus/Grafana/Loki — ele opera em paralelo, correlacionando os alertas gerados por
essas ferramentas com os dados de APM do New Relic (traces distribuídos, erros de
aplicação) para reduzir ruído e apontar causa provável, encurtando a fase de Triagem
descrita na Seção 3.

---

## 2. Configuração de AIOps no New Relic

### 2.1 Applied Intelligence — detecção automática de anomalias comportamentais

O Applied Intelligence usa modelos estatísticos (não limiares fixos) para estabelecer uma
baseline de comportamento normal por métrica — latência, taxa de erro, throughput — e
sinaliza desvios como anomalias antes que um limiar estático seja violado. Isso é
particularmente útil para o `donation-service`, cujo tráfego varia por campanha (picos
sazonais como Natal), tornando limiares fixos menos precisos que uma baseline adaptativa.

### 2.2 Correlação de alertas (redução de ruído)

Quando múltiplos alertas disparam para o mesmo incidente subjacente — por exemplo,
latência alta no `donation-service` + timeout no SQS + erro 5xx correlacionado — o Applied
Intelligence agrupa esses sinais em um único **incident**, em vez de gerar notificações
separadas para cada alerta. Isso evita fadiga de alerta (alert fatigue) do time de plantão
e concentra a triagem em um único ponto de entrada.

### 2.3 Como acessar

```
New Relic → Alerts → Applied Intelligence
```

A partir dessa tela é possível:
- Visualizar incidents correlacionados em tempo real
- Inspecionar a baseline de anomalia calculada por métrica
- Configurar políticas de correlação (janela de tempo, entidades relacionadas)

Passo a passo completo de ativação em `gitops/monitoring/newrelic-alert-policy.md`.

### 2.4 Política de alertas sugerida — donation-service

| Condição | Limiar | Duração | Severidade |
|---|---|---|---|
| Latência P99 (`POST /donations`) | > 400ms | > 5 minutos | **Warning** |
| Latência P99 (`POST /donations`) | > 500ms | > 2 minutos | **Critical** |
| Taxa de erros 5xx | > 0.05% | — | **Warning** |
| Taxa de erros 5xx | > 0.1% | — | **Critical** |
| Pod indisponível (`donation-service`) | 0 réplicas Ready | > 1 minuto | **Critical** |

**Alinhamento com o SLO formal:** os limiares de 500ms/0.1% replicam exatamente o SLO
definido em `docs/SRE.md`, seção 2 — o alerta Critical dispara exatamente quando o
error budget está sendo consumido, não antes nem depois. Os limiares de Warning (400ms /
0.05%) atuam como aviso antecipado, dando à equipe uma janela de reação antes que o SLO
seja formalmente violado.

---

## 3. Fluxo de Vida de um Incidente (ITSM)

Ciclo completo em 5 fases, do primeiro sinal de anomalia ao aprendizado documentado:

### Fase 1 — Detecção (0–5 min)

- New Relic Applied Intelligence detecta anomalia comportamental (ou Prometheus
  Alertmanager dispara um alerta de limiar, ver `docs/SRE.md` seção 7.2)
- Alerta dispara via webhook/e-mail/Slack conforme a severidade (Seção 5)
- On-call engineer recebe a notificação

### Fase 2 — Triagem (5–15 min)

- Verificar o dashboard SRE no Grafana (`gitops/monitoring/sre-dashboard.yaml`) — painéis
  de disponibilidade, error budget e CPU/memória do `donation-service`
- Checar logs no Loki, filtrados por pod e janela de tempo do incidente
- Verificar traces distribuídos no New Relic APM para localizar o span com maior latência
  ou o ponto de falha
- Classificar severidade (P1/P2/P3 — ver Seção 4)

### Fase 3 — Contenção (15–30 min)

- **P1** (donation-service down): rollback via ArgoCD (`argocd app rollback donation-service`)
- **P2** (degradação de performance): escalar réplicas do Deployment como mitigação
  temporária enquanto a causa raiz é investigada
- **P3** (erro isolado): investigar logs e corrigir sem necessidade de rollback imediato

### Fase 4 — Resolução (30 min – 4h)

- Aplicar fix definitivo via GitOps: PR → merge → ArgoCD detecta e sincroniza o deploy
- Validar que as métricas voltam ao normal no dashboard Grafana (Seção 2 do `docs/SRE.md`)
- Comunicar stakeholders — ONGs parceiras — sobre resolução e impacto real (Seção 5)

### Fase 5 — Post-Mortem (até 48h após a resolução)

- Preencher o template de post-mortem blameless (Seção 6)
- Atualizar `docs/RUNBOOK.md` se o incidente revelar um procedimento não documentado ou
  um passo manual que deveria ser automatizado

---

## 4. Classificação de Severidade

| Severidade | Critério | Tempo de resposta (TTA) | Ação imediata |
|---|---|---|---|
| **P1 — Crítico** | `donation-service` totalmente indisponível ou taxa de erro 5xx > 0.1% sustentada | < 5 minutos | Rollback imediato via ArgoCD; acionamento de plantão 24/7 |
| **P2 — Alto** | Degradação de performance (latência P99 > 500ms) sem indisponibilidade total; `ngo-service` fora do ar | < 15 minutos | Escalar réplicas; investigar causa raiz em paralelo |
| **P3 — Médio** | Erro isolado e não recorrente; `volunteer-service` degradado ou fora do ar | < 1 hora (horário comercial) | Investigar logs; corrigir no próximo ciclo de deploy |
| **P4 — Baixo** | Comportamento cosmético ou melhoria identificada sem impacto funcional | Próximo sprint | Registrar no backlog; sem ação imediata |

---

## 5. Canais de Comunicação por Severidade

| Severidade | Canais acionados |
|---|---|
| **P1** | PagerDuty (acionamento de plantão) + Slack `#incidents` + e-mail às ONGs parceiras afetadas |
| **P2** | Slack `#incidents` + e-mail ao time técnico |
| **P3** | Slack `#alerts` + ticket registrado no backlog |
| **P4** | Ticket registrado no backlog |

**Racional:** a comunicação escala com o impacto real ao negócio. Apenas incidentes P1
justificam contato direto com ONGs parceiras — comunicação excessiva para incidentes
menores gera fadiga e reduz a credibilidade dos alertas quando um P1 de fato ocorrer.

---

## 6. Template de Post-Mortem Blameless

```markdown
# Post-Mortem — <título curto do incidente>

## Data e Duração
- Data do incidente: <AAAA-MM-DD>
- Início da detecção: <HH:MM>
- Início da resolução: <HH:MM>
- Duração total: <XX min>

## Severidade e Impacto
- Severidade: <P1 | P2 | P3 | P4>
- Serviço(s) afetado(s): <donation-service | ngo-service | volunteer-service>
- Impacto no negócio: <ex.: N doações não processadas / não houve perda de dados>
- Usuários/ONGs afetados: <estimativa ou lista>

## Timeline Detalhada
| Horário | Evento |
|---|---|
| HH:MM | Anomalia detectada pelo New Relic Applied Intelligence / alerta Prometheus disparado |
| HH:MM | On-call notificado via <canal> |
| HH:MM | Triagem iniciada — dashboard Grafana / logs Loki / traces New Relic verificados |
| HH:MM | Severidade classificada como <P1/P2/P3> |
| HH:MM | Ação de contenção aplicada: <rollback / scale / investigação> |
| HH:MM | Causa raiz identificada |
| HH:MM | Fix aplicado via GitOps (PR #<número>) |
| HH:MM | Métricas confirmadas normalizadas no Grafana |
| HH:MM | Incidente encerrado |

## Causa Raiz (5 Whys)
1. Por que o incidente ocorreu? <resposta>
2. Por que <resposta 1>? <resposta>
3. Por que <resposta 2>? <resposta>
4. Por que <resposta 3>? <resposta>
5. Por que <resposta 4>? <causa raiz final>

## O Que Funcionou Bem
- <ex.: alerta disparou dentro da meta de TTD>
- <ex.: rollback via ArgoCD levou menos de 5 minutos>

## O Que Pode Melhorar
- <ex.: dashboard não tinha painel para a métrica que causou o problema>
- <ex.: runbook não cobria esse cenário específico>

## Ações Corretivas
| Ação | Responsável | Prazo |
|---|---|---|
| <ex.: adicionar painel X ao dashboard SRE> | <nome> | <AAAA-MM-DD> |
| <ex.: atualizar RUNBOOK.md com procedimento Y> | <nome> | <AAAA-MM-DD> |
| <ex.: criar alerta preventivo para Z> | <nome> | <AAAA-MM-DD> |

---
> Este post-mortem é blameless: o objetivo é identificar falhas de processo e sistema,
> nunca atribuir culpa individual. Erros humanos são sintomas de lacunas em processo,
> automação ou documentação — é isso que este documento existe para corrigir.
```

---

## 7. Métricas de ITSM

| Métrica | Definição | Meta | Fonte |
|---|---|---|---|
| **MTTR** (Mean Time To Resolve) | Tempo entre detecção e mitigação completa | **< 22 minutos** | Consolidado em `docs/SRE.md`, seção 7 (TTD+TTN+TTDiag+TTM) |
| **MTTA** (Mean Time To Acknowledge) | Tempo entre disparo do alerta e reconhecimento pelo on-call | **< 5 minutos** | PagerDuty / Slack (registro de ack) |
| **MTTD** (Mean Time To Detect) | Tempo entre início real do problema e detecção automática | **< 2 minutos** | New Relic Applied Intelligence (detecção comportamental) |
| **Taxa de incidentes recorrentes** | % de incidentes cuja causa raiz já havia sido identificada em post-mortem anterior | **< 10%** | Revisão de post-mortems (Seção 6) por trimestre |

A meta de MTTD de < 2 minutos com Applied Intelligence é mais agressiva que o TTD de
< 5 minutos definido em `docs/SRE.md` para o Alertmanager baseado em limiares — reflexo
direto do valor do AIOps: detecção comportamental antecipa a violação de limiar fixo.
Uma taxa de recorrência acima de 10% indica que as ações corretivas dos post-mortems
(Seção 6) não estão sendo executadas ou não estão endereçando a causa raiz real.

---

_Documento correspondente à Etapa 9 (ITSM/AIOps) do CONTEXT.md, seção 6. Ver também
`gitops/monitoring/newrelic-alert-policy.md` para o passo a passo de configuração do
Applied Intelligence e das políticas de alerta no console do New Relic._
