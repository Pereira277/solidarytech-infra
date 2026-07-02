# RUNBOOK — SolidaryTech Infra

> Documento operacional do projeto SolidaryTech (Hackathon POSTECH Fase 5).
> Atualizar a cada novo componente criado/modificado.

---

## 1. Estrutura do Projeto

### Repositórios

| Repositório | Finalidade |
|---|---|
| `solidarytech-infra` | Infraestrutura Terraform + manifests GitOps para ArgoCD |
| `solidarytech-ngo` | Código-fonte do ngo-service (Python/Flask) |
| `solidarytech-donation` | Código-fonte do donation-service (Go) — Hot Path |
| `solidarytech-volunteer` | Código-fonte do volunteer-service (Python/Flask) |

### Como navegar entre os repositórios

```
FIAP/Fase5/
├── CONTEXT.md              ← fonte da verdade do projeto (ler antes de qualquer ação)
├── CLAUDE.md               ← instruções do Claude Code
├── hackathon-DCLT/         ← código-fonte original (somente leitura)
├── solidarytech-infra/     ← este repositório
├── solidarytech-ngo/
├── solidarytech-donation/
└── solidarytech-volunteer/
```

### Estrutura interna do solidarytech-infra

```
solidarytech-infra/
├── bootstrap-s3/           ← PERMANENTE — criar bucket S3 de state (executar 1x, NUNCA destruir)
├── bootstrap-ecr/          ← PERMANENTE — criar repos ECR (executar 1x, NUNCA destruir)
├── infra/
│   └── terraform/          ← EFÊMERO — VPC, EKS, RDS, DynamoDB, SQS, Velero-S3 (sobe/desce por sessão)
├── gitops/
│   ├── argocd/             ← ArgoCD Application YAMLs (um por workload)
│   ├── ngo-service/        ← Kubernetes manifests do ngo-service
│   ├── donation-service/   ← Kubernetes manifests do donation-service
│   ├── volunteer-service/  ← Kubernetes manifests do volunteer-service
│   └── ingress/            ← Ingress resources (ALB Ingress Controller)
└── docs/                   ← documentação operacional
    ├── RUNBOOK.md          ← este arquivo
    ├── SRE.md
    ├── FINOPS.md
    ├── PCN.md
    └── ITSM.md
```

### Regra de ouro

- **Terraform** é executado **manualmente via terminal** (sem pipeline CI/CD de infra).
- **Aplicações** (ngo, donation, volunteer) têm pipeline GitHub Actions nos seus próprios repositórios.
- **GitOps** é gerenciado pelo ArgoCD apontando para `solidarytech-infra/gitops/`.

---

## 2. Microsserviços — Referência Rápida

| Serviço | Porta | Banco | Endpoints principais |
|---|---|---|---|
| ngo-service | 8081 | PostgreSQL (RDS) | `POST /ngos`, `GET /ngos`, `GET /health` |
| donation-service | 8082 | PostgreSQL (RDS) + SQS | `POST /donations`, `GET /donations`, `GET /health` |
| volunteer-service | 8083 | DynamoDB | `POST /volunteers`, `GET /volunteers/{ngo_id}`, `GET /health` |

---

---

## 3. Ciclo de Vida das Camadas Terraform

| Camada | Pasta | Ciclo de Vida | Backend |
|---|---|---|---|
| Bootstrap S3 | `bootstrap-s3/` | **Permanente** — aplicar 1x, NUNCA destruir | Local |
| Bootstrap ECR | `bootstrap-ecr/` | **Permanente** — aplicar 1x, NUNCA destruir | Local |
| Infra Principal | `infra/terraform/` | **Efêmero** — sobe/desce a cada sessão de estudo | S3 |

> **AVISO CRÍTICO:** Destruir o bootstrap-s3 apaga o bucket que guarda o state da infra principal — você perde o controle de todos os recursos AWS criados. Destruir o bootstrap-ecr invalida as URLs dos repositórios usadas nos pipelines CI/CD de todos os microsserviços.

---

## 4. Início de Sessão AWS Academy

A cada nova sessão do AWS Academy as credenciais expiram. Antes de qualquer comando Terraform ou AWS CLI:

1. Acesse [https://awsacademy.instructure.com](https://awsacademy.instructure.com) → seu curso → **Módulos** → **Learner Lab** → **Start Lab**
2. Clique em **AWS Details** → **AWS CLI** → copie as três variáveis
3. Cole no terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Verificar que as credenciais são válidas:
aws sts get-caller-identity
# Esperado: Account = 354132155257
```

> As credenciais do AWS Academy duram ~4 horas. Se um comando falhar com `ExpiredTokenException`, repita os passos acima.

---

## 5. Bootstrap — Executar Apenas Uma Vez

> Execute estes passos **uma única vez** para preparar a infraestrutura permanente.
> Após aplicado com sucesso, **não execute `terraform destroy` nestas pastas nunca**.

### 5.1 Bootstrap S3 (bucket de state)

```bash
cd solidarytech-infra/bootstrap-s3/

terraform init
terraform plan -out=plan.out
terraform apply plan.out

# Anote o output:
terraform output bucket_name
# Esperado: solidarytech-terraform-state-354132155257
```

### 5.2 Bootstrap ECR (repositórios de imagens)

```bash
cd ../bootstrap-ecr/

terraform init
terraform plan -out=plan.out
terraform apply plan.out

# Anote os outputs — serão usados nos pipelines CI/CD:
terraform output
# ngo_repository_url      = "354132155257.dkr.ecr.us-east-1.amazonaws.com/solidarytech-ngo"
# donation_repository_url = "354132155257.dkr.ecr.us-east-1.amazonaws.com/solidarytech-donation"
# volunteer_repository_url= "354132155257.dkr.ecr.us-east-1.amazonaws.com/solidarytech-volunteer"
```

---

## 6. Subir Infra da Sessão

Execute a cada início de sessão de estudo, após exportar as credenciais (seção 4).

```bash
cd solidarytech-infra/infra/terraform/

# Copiar tfvars na primeira vez:
# cp terraform.tfvars.example terraform.tfvars

terraform init   # necessário após expiração de credenciais (re-autentica no backend S3)
terraform plan -out=plan.out
terraform apply plan.out
```

---

## 7. Encerrar Sessão

Execute ao final de cada sessão de estudo para economizar créditos AWS Academy.

```bash
cd solidarytech-infra/infra/terraform/

terraform destroy
# Confirmar com: yes
```

> **AVISO:** `terraform destroy` deve ser executado APENAS em `infra/terraform/`.
> **NUNCA execute `terraform destroy` em `bootstrap-s3/` ou `bootstrap-ecr/`.**

---

## 8. Pipelines CI/CD — fluxo build → scan → push ECR → update GitOps

Cada repositório de microsserviço (`solidarytech-ngo`, `solidarytech-donation`, `solidarytech-volunteer`) tem um pipeline GitHub Actions em `.github/workflows/ci-cd.yml` com 4 estágios em série:

### Estágio 1 — build-and-test

| Serviço | Ação |
|---|---|
| donation-service (Go) | `go mod download` → `go build ./...` |
| ngo-service (Python) | `pip install -r requirements.txt` → `python -m py_compile app.py` |
| volunteer-service (Python) | `pip install -r requirements.txt` → `python -m py_compile app.py` |

### Estágio 2 — security-and-lint

| Ferramenta | Serviços | O que verifica |
|---|---|---|
| golangci-lint | donation | Análise estática Go (múltiplos linters) |
| gosec | donation | Vulnerabilidades de segurança Go (SAST) |
| flake8 | ngo, volunteer | Estilo e erros Python (max-line-length=120) |
| bandit | ngo, volunteer | Vulnerabilidades de segurança Python (SAST) |
| Trivy (filesystem) | todos | CVEs críticos em dependências (SCA); exit-code 1 se CRITICAL |

### Estágio 3 — docker-build-and-scan

1. Autentica no ECR via `aws-actions/configure-aws-credentials` + `amazon-ecr-login`
2. Constrói a imagem com tag `github.sha` (nunca `latest` como única tag)
3. Trivy varre a imagem (container scan) — bloqueia push se CRITICAL
4. Faz push para o ECR apenas se o scan passar

### Estágio 4 — update-gitops

1. Faz checkout do repo `Pereira277/solidarytech-infra` usando `GITOPS_PAT`
2. Substitui a tag da imagem no Deployment YAML via `sed`
3. Commit e push — o ArgoCD detecta a mudança e reconcilia

### Secrets necessários em cada repo de microsserviço

```
AWS_ACCESS_KEY_ID       — credencial AWS Academy
AWS_SECRET_ACCESS_KEY   — credencial AWS Academy
AWS_SESSION_TOKEN       — obrigatório no AWS Academy (expira em ~4h)
GITOPS_PAT              — Personal Access Token com acesso de escrita ao solidarytech-infra
```

### Como verificar que a pipeline funcionou

```bash
# Ver imagens no ECR (após pipeline concluir):
aws ecr list-images --repository-name solidarytech-donation --region us-east-1
aws ecr list-images --repository-name solidarytech-ngo      --region us-east-1
aws ecr list-images --repository-name solidarytech-volunteer --region us-east-1

# Verificar que o deployment YAML foi atualizado no repo gitops:
cd solidarytech-infra
git log --oneline gitops/donation-service/donation-deployment.yaml
```

### Diagrama do fluxo

```
push → main
  └─ build-and-test
       └─ security-and-lint  (SAST + SCA)
            └─ docker-build-and-scan  (Trivy container + push ECR)
                 └─ update-gitops  (sed tag → commit → push)
                      └─ ArgoCD detecta diff → sync → deploy no EKS
```

---

## 9. Infraestrutura Principal (Etapa 3) — VPC, EKS, RDS, SQS, DynamoDB, Velero S3

### Recursos provisionados

| Recurso | Identificador | Região |
|---|---|---|
| VPC | `solidarytech-vpc` (`10.0.0.0/16`) | us-east-1 |
| Subnets públicas | `solidarytech-public-a/b` (`10.0.1/2.0/24`) | us-east-1a/b |
| Subnets privadas | `solidarytech-private-a/b` (`10.0.11/12.0/24`) | us-east-1a/b |
| Subnets de banco | `solidarytech-db-a/b` (`10.0.21/22.0/24`) | us-east-1a/b |
| Internet Gateway | `solidarytech-igw` | us-east-1 |
| NAT Gateway | `solidarytech-nat` (EIP em public-a) | us-east-1 |
| EKS Cluster | `solidarytech-cluster` (k8s 1.32) | us-east-1 |
| EKS Node Group | `solidarytech-nodes` (2x t3.medium ON_DEMAND) | us-east-1a/b |
| RDS PostgreSQL 17 | `solidarytech-ngo-db` / `solidarytech-donation-db` (db.t3.micro) | us-east-1 |
| SQS Standard | `solidarytech-donation-events` | us-east-1 |
| DynamoDB | `solidarytech-volunteers` (PAY_PER_REQUEST) | us-east-1 |
| S3 Velero | `solidarytech-velero-354132155257` (versionado) | us-east-2 |

### Pré-requisitos por sessão

```bash
# 1. Exportar credenciais AWS Academy (veja seção 4)
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# 2. Definir senhas dos bancos (nunca em arquivo)
export TF_VAR_ngo_db_password="<senha-forte>"
export TF_VAR_donation_db_password="<senha-forte>"

# Regras de senha RDS: mínimo 8 chars, sem /, @, espaço
```

### Subir a infra

```bash
cd solidarytech-infra/infra/terraform/

terraform init        # re-executa após rotação de credenciais
terraform validate    # verifica sintaxe
terraform plan -out=plan.out
terraform apply plan.out

# Verificar outputs após apply:
terraform output
```

### Verificar recursos criados

```bash
# EKS
aws eks describe-cluster --name solidarytech-cluster --region us-east-1 \
  --query 'cluster.status'
# Esperado: "ACTIVE"

# Nodes
aws eks list-nodegroups --cluster-name solidarytech-cluster --region us-east-1

# RDS
aws rds describe-db-instances --region us-east-1 \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table

# SQS
aws sqs get-queue-url --queue-name solidarytech-donation-events --region us-east-1

# DynamoDB
aws dynamodb describe-table --table-name solidarytech-volunteers --region us-east-1 \
  --query 'Table.TableStatus'
# Esperado: "ACTIVE"

# S3 Velero (DR)
aws s3 ls s3://solidarytech-velero-354132155257 --region us-east-2
```

### Configurar kubectl após apply

```bash
aws eks update-kubeconfig \
  --name solidarytech-cluster \
  --region us-east-1

kubectl get nodes
# Esperado: 2 nodes em Ready
```

### Derrubar a infra (fim de sessão)

```bash
cd solidarytech-infra/infra/terraform/

# Passwords devem estar exportados para o destroy não pedir input:
export TF_VAR_ngo_db_password="<mesma-senha-usada-no-apply>"
export TF_VAR_donation_db_password="<mesma-senha-usada-no-apply>"

terraform destroy
# Confirmar com: yes
```

> **AVISO:** O bucket S3 do Velero (`solidarytech-velero-*`) em us-east-2 é destruído junto.
> Isso é intencional — em ambiente Academy com créditos limitados, manter buckets ociosos gera custo.

### Observações de IAM

Em AWS Academy não é possível criar IAM roles. Todos os recursos EKS usam a role `LabRole` pré-existente na conta:
- `data "aws_iam_role" "eks_cluster_role"` → `LabRole`
- `data "aws_iam_role" "eks_node_role"` → `LabRole`

A `LabRole` na AWS Academy já tem as políticas `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` e `AmazonEC2ContainerRegistryReadOnly` anexadas.

---

## 10. GitOps e Deploy (Etapa 4) — ArgoCD + Secrets + Banco

### Pré-requisitos

- Credenciais AWS Academy exportadas (seção 4)
- kubectl apontando para `solidarytech-cluster` (seção 9)
- `$TF_VAR_ngo_db_password` e `$TF_VAR_donation_db_password` exportados

### 10.1 Instalar ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aguardar todos os pods ficarem Running (leva ~2 min):
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=300s

kubectl get pods -n argocd
```

### 10.2 Criar namespace solidarytech e Secrets

```bash
# Namespace (declarativo — idempotente):
kubectl apply -f solidarytech-infra/gitops/namespace.yaml

# ngo-service-secret
kubectl create secret generic ngo-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_ngo_db_password}@solidarytech-ngo-db.csxznhqparxp.us-east-1.rds.amazonaws.com:5432/ngodb"

# donation-service-secret
kubectl create secret generic donation-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_donation_db_password}@solidarytech-donation-db.csxznhqparxp.us-east-1.rds.amazonaws.com:5432/donationdb" \
  --from-literal=AWS_SQS_URL="https://sqs.us-east-1.amazonaws.com/354132155257/solidarytech-donation-events" \
  --from-literal=AWS_REGION="us-east-1"

# volunteer-service-secret
# AWS Academy does not support IRSA — credentials must be injected explicitly.
# Recreate this secret at every session with the current Academy credentials.
kubectl create secret generic volunteer-service-secret \
  --namespace solidarytech \
  --from-literal=AWS_DYNAMODB_TABLE="solidarytech-volunteers" \
  --from-literal=AWS_REGION="us-east-1" \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}"

# After recreating the secret, restart the deployment to pick up new credentials:
# kubectl rollout restart deployment volunteer-service -n solidarytech

# Verificar:
kubectl get secrets -n solidarytech
```

> **AVISO — volunteer-service:** O `AWS_SESSION_TOKEN` do AWS Academy expira em ~4h.
> A cada nova sessão é necessário recriar o secret `volunteer-service-secret` com as
> novas credenciais e executar `kubectl rollout restart deployment volunteer-service -n solidarytech`.

### 10.3 Aplicar ArgoCD Applications

```bash
kubectl apply -f solidarytech-infra/gitops/argocd/ngo-application.yaml
kubectl apply -f solidarytech-infra/gitops/argocd/donation-application.yaml
kubectl apply -f solidarytech-infra/gitops/argocd/volunteer-application.yaml

# Verificar sync status:
kubectl get applications -n argocd
```

### 10.4 Inicializar bancos de dados (via pod temporário)

Executar os scripts `db/init.sql` a partir de um pod temporário com acesso à rede interna do cluster:

```bash
# ngo-db — cria tabela ngos e insere seeds
kubectl run psql-ngo --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_ngo_db_password}" \
  -- psql -h solidarytech-ngo-db.csxznhqparxp.us-east-1.rds.amazonaws.com \
         -U solidarytech -d ngodb \
         -c "$(cat solidarytech-ngo/db/init.sql)"

# donation-db — cria tabela donations
kubectl run psql-donation --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_donation_db_password}" \
  -- psql -h solidarytech-donation-db.csxznhqparxp.us-east-1.rds.amazonaws.com \
         -U solidarytech -d donationdb \
         -c "$(cat solidarytech-donation/db/init.sql)"

# volunteer-service — sem init.sql (DynamoDB já criado pelo Terraform)
```

### 10.5 Validar deploy

```bash
# Pods em solidarytech:
kubectl get pods -n solidarytech

# Services:
kubectl get svc -n solidarytech

# Verificar logs se pod não estiver Running:
kubectl logs -n solidarytech <pod-name>

# Verificar eventos se pod estiver em CrashLoopBackOff:
kubectl describe pod -n solidarytech <pod-name>
```

### 10.6 Acessar ArgoCD UI (opcional)

```bash
# Port-forward para UI do ArgoCD:
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Senha inicial do admin:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Acesse: https://localhost:8080 (usuário: admin)
```

---

## 11. Observabilidade (Etapa 5) — Prometheus, Grafana, Loki, OpenTelemetry

### Componentes

| Componente | Tipo | Namespace | Acesso |
|---|---|---|---|
| kube-prometheus-stack | Helm chart via ArgoCD | monitoring | Grafana via LoadBalancer |
| Loki + Promtail | Helm chart via ArgoCD | monitoring | Interno (via Grafana datasource) |
| OpenTelemetry Collector | Manifests no repo via ArgoCD | monitoring | ClusterIP portas 4317/4318 |

### 11.1 Criar secret do New Relic

Obter a License Key em: **https://one.newrelic.com → API Keys → INGEST - LICENSE**

```bash
kubectl create namespace monitoring

kubectl create secret generic new-relic-secret \
  --namespace monitoring \
  --from-literal=NEW_RELIC_LICENSE_KEY="<sua-license-key>"
```

### 11.2 Aplicar ArgoCD Applications

```bash
kubectl apply -f solidarytech-infra/gitops/argocd/prometheus-grafana-application.yaml
kubectl apply -f solidarytech-infra/gitops/argocd/loki-application.yaml
kubectl apply -f solidarytech-infra/gitops/argocd/otel-collector-application.yaml

# Acompanhar sync:
kubectl get applications -n argocd
```

### 11.3 Aguardar pods do monitoring ficarem Ready

```bash
# kube-prometheus-stack leva ~3-5 min:
kubectl wait --for=condition=Ready pod --all -n monitoring --timeout=600s

kubectl get pods -n monitoring
```

### 11.4 Acessar o Grafana

```bash
# Obter o External IP do LoadBalancer do Grafana:
kubectl get svc -n monitoring | grep grafana

# Acesse: http://<EXTERNAL-IP>
# Usuário: admin
# Senha:   SolidaryAdmin2024!
```

### 11.5 Configurar Loki como datasource no Grafana

1. Grafana → **Configuration** → **Data Sources** → **Add data source** → **Loki**
2. URL: `http://loki:3100`
3. **Save & Test**

### 11.6 Verificar traces chegando no New Relic

```bash
# Checar logs do collector para confirmar exportação:
kubectl logs -n monitoring deployment/otel-collector | grep -i "export"
```

Acesse **https://one.newrelic.com → APM & Services** — os 3 serviços devem aparecer após as primeiras requisições.

### 11.7 Verificar métricas do cluster no Grafana

- Dashboard pré-instalado: **Kubernetes / Compute Resources / Cluster**
- Dashboard pré-instalado: **Kubernetes / Compute Resources / Namespace (Pods)**
- Importar dashboard Loki: ID **12019** (Loki & Promtail)

### 11.8 Troubleshooting — Prometheus StatefulSet não sobe

**Sintoma:** `kubectl get statefulset -n monitoring` não mostra o Prometheus;
`kubectl get prometheus -n monitoring` mostra coluna RECONCILED vazia.

**Causa:** CRD `prometheuses.monitoring.coreos.com` com annotations grandes demais
para etcd — ArgoCD usa client-side apply que falha no CRD do kube-prometheus-stack.

**Solução:**

```bash
# 1. Aplicar o CRD via server-side apply (ignora limite de annotation):
kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.71.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml

# 2. Reiniciar o operador para reconciliar:
kubectl rollout restart deployment prometheus-grafana-kube-pr-operator -n monitoring

# 3. Verificar reconciliação (aguardar RECONCILED = True):
kubectl get prometheus -n monitoring
```

### 11.9 Troubleshooting — Grafana sem datasource / dashboards com "No data"

**Sintoma:** dashboards mostram _"No data sources found"_ ou _"Datasource was not found"_;
ou erro _"Only one datasource per organization can be marked as default"_ nos logs do Grafana.

**Causa raiz confirmada (via inspeção do chart source):**

O template `templates/datasources.yaml` do loki-stack 2.10.2:
```
{{- if .Values.grafana.sidecar.datasources.enabled }}
...
  isDefault: {{ default false .Values.loki.isDefault }}
```

- `helm.parameters` passa o valor como **string** `"false"`. Go template avalia `if "false"` como **truthy** → ConfigMap sempre criado, independentemente do valor.
- `loki.isDefault` padrão no chart é `true`. Tentativas de setar via `parameters` falham pelo mesmo motivo de tipo.

**Solução definitiva aplicada:**

1. `loki-application.yaml` usa `helm.values` (bloco YAML com boolean real) e define `grafana.sidecar.datasources.enabled: false` → template `{{- if false }}` pula o bloco → ConfigMap do chart **não é criado**.
2. `gitops/monitoring/loki-datasource.yaml` — nosso próprio ConfigMap com `isDefault: false`, gerenciado pelo ArgoCD via `monitoring-config` Application.

**Para aplicar no cluster:**

```bash
# 1. Deletar o ConfigMap antigo do chart (se existir):
kubectl delete configmap loki-loki-stack -n monitoring --ignore-not-found

# 2. Aplicar o novo ArgoCD Application que gerencia o nosso ConfigMap:
kubectl apply -f solidarytech-infra/gitops/argocd/monitoring-application.yaml

# 3. Hard refresh do Loki para reprocessar com os novos helm.values:
kubectl annotate application loki -n argocd argocd.argoproj.io/refresh=hard

# 4. Verificar que o ConfigMap correto existe:
kubectl get configmap -n monitoring loki-datasource -o yaml | grep isDefault
# Esperado: isDefault: false

kubectl get configmap -n monitoring loki-loki-stack 2>&1
# Esperado: Error from server (NotFound) — não deve mais existir

# 5. Reiniciar Grafana para recarregar datasources:
kubectl rollout restart deployment prometheus-grafana -n monitoring

# 6. Verificar datasources no Grafana UI:
#    Configuration → Data Sources → Prometheus (default) + Loki (não default)
```

---

_Seções adicionais serão acrescentadas conforme cada componente for criado (Etapas 6–9)._
