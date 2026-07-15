# PCN.md — Plano de Continuidade de Negócios: SolidaryTech

> Documento formal de PCN/DR — Frente 4 do Hackathon POSTECH Fase 5 (DCLT).
> Responsável técnico: Lucas Pereira — Turma POSTECH 2026.

---

## 1. Objetivo e Escopo

Este documento define a estratégia de continuidade de negócios da plataforma SolidaryTech
diante de cenários de perda de dados ou indisponibilidade do cluster EKS — namespace
corrompido, deleção acidental de recursos, ou falha catastrófica do cluster.

**Foco principal:** `donation-service`, classificado como Hot Path (ver `docs/SRE.md`).
É o único ponto de processamento de doações financeiras da plataforma: toda receita das
ONGs parceiras depende de sua disponibilidade e da integridade dos dados armazenados em
seu banco PostgreSQL. Qualquer estratégia de DR que não cubra o `donation-service` com a
prioridade máxima é insuficiente para o negócio.

O escopo cobre os 3 microsserviços (`donation-service`, `ngo-service`, `volunteer-service`)
e a camada de observabilidade (Prometheus, Grafana, Loki, OTel Collector), com estratégias
de backup diferenciadas por criticidade (Seção 2).

**Fora do escopo:** este documento cobre recuperação de manifestos Kubernetes e configuração
do cluster. A persistência de dados dos microsserviços (RDS PostgreSQL e DynamoDB) já possui
durabilidade nativa da AWS e não depende do Velero para sobreviver a uma falha de node ou pod —
o Velero neste ambiente cobre a camada de orquestração (Deployments, Services, Secrets,
ConfigMaps, Schedules), não o conteúdo dos bancos gerenciados.

---

## 2. Análise de Impacto (BIA — Business Impact Analysis)

| Serviço | Impacto de indisponibilidade | Criticidade | Justificativa |
|---|---|---|---|
| `donation-service` | Doações não processadas — receita das ONGs interrompida em tempo real | **CRÍTICO** | Hot Path da plataforma; sem ele, nenhuma doação chega ao destino (ver `docs/SRE.md` seção 1) |
| `ngo-service` | ONGs não conseguem se cadastrar nem atualizar seus dados | **ALTO** | Bloqueia onboarding de novas ONGs parceiras, mas não afeta doações já em andamento |
| `volunteer-service` | Voluntários não conseguem se registrar nem consultar campanhas | **MÉDIO** | Impacta engajamento e capilaridade social, sem impacto financeiro direto |

**Ordem de prioridade de restore em caso de incidente total do cluster:**
1. `donation-service` (+ dependências: RDS `donation-db`, SQS `donation-events`)
2. `ngo-service` (+ RDS `ngo-db`)
3. `volunteer-service` (+ DynamoDB `volunteers`)
4. Camada de observabilidade (Prometheus, Grafana, Loki, OTel Collector)

---

## 3. Valores de RPO e RTO

| Parâmetro | Valor | Justificativa |
|---|---|---|
| **RPO** (Recovery Point Objective) | **1 hora** | Backup Velero do namespace `solidarytech` agendado a cada hora (`0 * * * *`). Em caso de incidente, a perda máxima de estado de manifestos (Secrets, ConfigMaps, Deployments) é de até 1 hora. Os dados transacionais (doações, ONGs, voluntários) residem em RDS e DynamoDB, com durabilidade própria da AWS — não estão sujeitos a esse RPO. |
| **RTO** (Recovery Time Objective) | **4 horas** | Tempo estimado para: (1) restaurar o cluster/namespace via `velero restore create`, (2) validar que os pods sobem corretamente com os Secrets restaurados, (3) confirmar conectividade com RDS/DynamoDB/SQS, e (4) validar os 3 endpoints `/health`. Contempla margem para troubleshooting manual, dado que o ambiente AWS Academy exige recriação de credenciais e possível reautenticação de tokens de sessão. |

**Por que 1 hora de RPO é aceitável:** o `donation-service` não persiste estado dentro do
cluster — todo dado transacional vai direto para o RDS a cada requisição. O que o Velero
protege é a configuração operacional (Deployments, Services, Secrets de conexão), que muda
com baixa frequência. Um RPO de 1 hora nesse contexto significa, na prática, "recriar a
topologia de 1 hora atrás", não "perder até 1 hora de doações".

**Por que 4 horas de RTO é realista:** o ambiente roda em AWS Academy, com credenciais que
expiram em ~4h e sem automação de restore completa (sem IRSA, sem Spot). O RTO reflete o
tempo real de operação manual documentado no `docs/RUNBOOK.md`, não um cenário ideal com
automação total.

---

## 4. Estratégia de DR com Velero

### 4.1 Como o Velero funciona neste ambiente

O Velero é instalado no namespace `velero` via Helm chart (`vmware-tanzu/helm-charts`,
chart `velero`, versão `7.2.1`), gerenciado por uma ArgoCD Application
(`gitops/argocd/velero-application.yaml`). Ele executa dois tipos de backup:

1. **Backup de manifestos Kubernetes** — Deployments, Services, Secrets, ConfigMaps e
   demais objetos da API do cluster, serializados e enviados para o bucket S3
   `solidarytech-velero-354132155257` (região us-east-1, o mesmo bucket já provisionado
   pelo Terraform na Etapa 3).
2. **Backup de volumes (PVCs)** — normalmente feito via snapshot de EBS. **Neste ambiente,
   está desabilitado** (ver Seção 4.3): nenhum dos 3 microsserviços usa PVC (todos são
   stateless, com dados em RDS/DynamoDB externos), então essa limitação não afeta a
   recuperação real da aplicação.

O plugin `velero-plugin-for-aws` é injetado via `initContainers` no pod do Velero e
fornece as APIs `BackupStorageLocation` (S3) e `VolumeSnapshotLocation` (EBS) usadas pelo
core do Velero. As credenciais AWS são fornecidas via secret Kubernetes `velero-credentials`
(sem IRSA — AWS Academy não suporta IAM Roles for Service Accounts).

### 4.2 Fluxo de backup automático agendado

Dois recursos `Schedule` (CRD `velero.io/v1`) são aplicados via ArgoCD Application
`velero-resources` (`gitops/argocd/velero-resources-application.yaml`, apontando para
`gitops/velero/`):

| Schedule | Namespace coberto | Frequência | TTL (retenção) | Motivo |
|---|---|---|---|---|
| `solidarytech-hourly` | `solidarytech` | A cada hora (`0 * * * *`) | 72h (3 dias) | Cobre o RPO de 1h dos 3 microsserviços |
| `monitoring-6h` | `monitoring` | A cada 6 horas (`0 */6 * * *`) | 48h (2 dias) | Observabilidade é reconstruível via ArgoCD (Helm charts); backup é conveniência, não requisito de RPO |

O controlador do Velero cria automaticamente um objeto `Backup` a cada disparo do
`Schedule`, nomeado `<schedule-name>-<timestamp>`, e expira (`ttl`) backups antigos —
mantendo o bucket S3 sob controle de custo.

### 4.3 Limitações no AWS Academy

- **Sem EBS snapshots** (`snapshotsEnabled: false`): a role `LabRole` do AWS Academy não
  possui as permissões IAM (`ec2:CreateSnapshot`, `ec2:DescribeSnapshots`, etc.) necessárias
  para o plugin AWS criar snapshots de volumes EBS. O backup se limita a manifestos K8s.
- **Sem Node Agent / restic-kopia** (`deployNodeAgent: false`): sem suporte a backup de
  dados de PVCs via File System Backup, consequência direta da limitação anterior.
- **Sem IRSA**: credenciais AWS do Velero são injetadas via secret Kubernetes estático
  (`velero-credentials`), recriado a cada sessão do AWS Academy junto com os demais
  secrets que dependem de `AWS_SESSION_TOKEN` (ver `docs/RUNBOOK.md`).
- **Impacto prático:** como nenhum dos 3 microsserviços usa armazenamento persistente em
  PVC, essas limitações não comprometem a recuperação da aplicação — os dados que
  realmente importam (doações, ONGs, voluntários) estão em RDS/DynamoDB, fora do escopo
  do Velero, com sua própria durabilidade gerenciada pela AWS.

---

## 5. Procedimento de Restore (Runbook de DR)

### 5.1 Pré-requisitos

```bash
# CLI do Velero instalado localmente (uma vez):
# https://velero.io/docs/main/basic-install/#install-the-cli

# kubectl apontando para o cluster solidarytech-cluster
aws eks update-kubeconfig --name solidarytech-cluster --region us-east-1
```

### 5.2 Identificar o backup a restaurar

```bash
# Listar backups disponíveis (mais recente primeiro):
velero backup get

# Inspecionar detalhes de um backup específico:
velero backup describe <backup-name> --details
```

### 5.3 Restaurar o namespace solidarytech

```bash
velero restore create --from-backup <backup-name> --include-namespaces solidarytech
```

### 5.4 Acompanhar o restore

```bash
# Status do restore:
velero restore get

# Detalhes e eventuais erros/warnings:
velero restore describe <restore-name> --details

# Logs completos:
velero restore logs <restore-name>
```

### 5.5 Validação pós-restore

```bash
# Pods devem voltar a Running:
kubectl get pods -n solidarytech

# Secrets restaurados (senhas de banco, SQS URL, credenciais DynamoDB):
kubectl get secrets -n solidarytech

# IMPORTANTE: se o restore ocorreu após expiração da sessão AWS Academy,
# o AWS_SESSION_TOKEN do secret volunteer-service-secret estará desatualizado —
# recriar o secret e reiniciar o deployment (ver docs/RUNBOOK.md, seção 10.2).

# Validar os 3 endpoints de health:
kubectl port-forward svc/donation-service -n solidarytech 8082:8082 &
curl -s http://localhost:8082/health
# Esperado: {"status":"ok","service":"donation-service"}
```

### 5.6 Restaurar apenas o monitoring (cenário de menor prioridade)

```bash
velero restore create --from-backup <monitoring-backup-name> --include-namespaces monitoring
```

---

## 6. Testes de DR

### 6.1 Validar que o backup está funcionando

```bash
# Confirmar que o Schedule está ativo e disparando:
kubectl get schedules -n velero

# Confirmar que backups estão sendo criados na frequência esperada:
velero backup get
# Esperado: um backup "solidarytech-hourly-<timestamp>" a cada hora

# Confirmar que o backup chegou ao S3:
aws s3 ls s3://solidarytech-velero-354132155257/backups/ --region us-east-1

# Verificar status "Completed" (não "PartiallyFailed" ou "Failed"):
velero backup describe <backup-name> | grep Phase
```

### 6.2 Simular um restore (teste controlado)

Procedimento recomendado para validar a estratégia de DR sem impactar o ambiente de produção:

```bash
# 1. Criar um backup sob demanda (não esperar o schedule):
velero backup create teste-dr-manual --include-namespaces solidarytech

# 2. Aguardar completar:
velero backup describe teste-dr-manual --details
# Esperado: Phase: Completed

# 3. Deletar deliberadamente um recurso não crítico para simular perda
#    (ex.: um ConfigMap ou ficar apenas com o Deployment de um serviço não-crítico):
kubectl delete deployment volunteer-service -n solidarytech

# 4. Confirmar que o recurso sumiu:
kubectl get deployment volunteer-service -n solidarytech
# Esperado: NotFound

# 5. Restaurar a partir do backup de teste:
velero restore create teste-dr-restore --from-backup teste-dr-manual \
  --include-namespaces solidarytech

# 6. Confirmar que o recurso voltou:
kubectl get deployment volunteer-service -n solidarytech
kubectl get pods -n solidarytech | grep volunteer-service
# Esperado: pod Running novamente

# 7. Limpeza pós-teste (remover artefatos do teste):
velero backup delete teste-dr-manual --confirm
velero restore delete teste-dr-restore --confirm
```

### 6.3 Frequência recomendada de teste

Executar o teste de restore controlado (Seção 6.2) a cada nova sessão relevante de estudo
em que o ambiente for recriado do zero — isso valida, na prática, tanto o backup quanto o
restore, sem depender de simular uma falha real do cluster.

---

_Documento correspondente à Etapa 8 (Disaster Recovery) do CONTEXT.md, seção 6. Ver também
`docs/RUNBOOK.md`, seção "Etapa 8 — DR", para procedimentos operacionais de instalação do
Velero, criação do secret de credenciais e comandos de backup/restore._
