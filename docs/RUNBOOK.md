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

> **AVISO CRÍTICO — Load Balancer do Grafana:** O kube-prometheus-stack cria um AWS
> Load Balancer (ELB/NLB) para o serviço `prometheus-grafana` no namespace `monitoring`.
> O Terraform não gerencia esse recurso. Se não removido antes do `terraform destroy`,
> o destroy travará na destruição da VPC com erro de dependência.

```bash
# PASSO OBRIGATÓRIO antes do terraform destroy — remover LB do Grafana:
kubectl delete svc prometheus-grafana -n monitoring --ignore-not-found

# Aguardar o AWS remover o Load Balancer (~2 min):
sleep 120

# Confirmar que não há mais LBs pendentes ligados ao cluster (opcional):
aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code]' --output table

# Agora destruir a infra:
cd ~/FIAP/Fase5/solidarytech-infra/infra/terraform/

# Passwords devem estar exportados para o destroy não pedir input:
export TF_VAR_ngo_db_password="<mesma-senha-usada-no-apply>"
export TF_VAR_donation_db_password="<mesma-senha-usada-no-apply>"

terraform destroy -auto-approve
```

> **AVISO:** `terraform destroy` deve ser executado APENAS em `infra/terraform/`.
> **NUNCA execute `terraform destroy` em `bootstrap-s3/` ou `bootstrap-ecr/`.**

### Se o destroy travar — Security Groups e ENIs órfãos

O `terraform destroy` pode travar na destruição da VPC se o EKS ou o ALB tiverem criado
Security Groups e ENIs fora do controle do Terraform. Sinais: destroy parado em
`aws_vpc.main` ou `aws_security_group` por mais de 10 minutos.

```bash
# 1. Identificar o VPC ID:
VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:Name,Values=solidarytech-vpc" \
  --query 'Vpcs[0].VpcId' --output text)
echo "VPC: $VPC_ID"

# 2. Verificar ENIs (Elastic Network Interfaces) ainda presos ao VPC:
aws ec2 describe-network-interfaces --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description,InterfaceType]' \
  --output table

# 3. Verificar Security Groups criados pelo EKS/ALB (fora do Terraform):
aws ec2 describe-security-groups --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' --output table
# SGs com nome "eks-cluster-sg-*" ou "k8s-elb-*" são criados pelo EKS/ALB.

# 4. Excluir SGs órfãos (substituir sg-XXXX pelos IDs listados acima;
#    ignorar os que têm dependência — excluir as ENIs primeiro):
# aws ec2 delete-security-group --group-id sg-XXXX --region us-east-1

# 5. Se houver ENIs em estado "available" (não anexadas), excluir:
# aws ec2 delete-network-interface --network-interface-id eni-XXXX --region us-east-1

# 6. Após limpar os órfãos, retomar o destroy:
terraform destroy -auto-approve
```

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

> Remover o LB do Grafana ANTES do destroy (veja a seção 7 — Encerrar Sessão).

```bash
cd ~/FIAP/Fase5/solidarytech-infra/infra/terraform/

# Passwords devem estar exportados para o destroy não pedir input:
export TF_VAR_ngo_db_password="<mesma-senha-usada-no-apply>"
export TF_VAR_donation_db_password="<mesma-senha-usada-no-apply>"

terraform destroy -auto-approve
```

> **AVISO:** O bucket S3 do Velero (`solidarytech-velero-*`) em us-east-2 é destruído junto.
> Isso é intencional — em ambiente Academy com créditos limitados, manter buckets ociosos gera custo.
> Se o destroy travar na VPC, ver seção 7 — "Se o destroy travar — Security Groups e ENIs órfãos".

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

# Pré-requisito: endpoints dinâmicos devem estar exportados.
# Execute no diretório infra/terraform/ ANTES destes comandos:
#   export NGO_DB_ENDPOINT=$(terraform output -raw ngo_db_endpoint)
#   export DONATION_DB_ENDPOINT=$(terraform output -raw donation_db_endpoint)
#   export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)

# ngo-service-secret
kubectl create secret generic ngo-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_ngo_db_password}@${NGO_DB_ENDPOINT}/ngodb"

# donation-service-secret
kubectl create secret generic donation-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_donation_db_password}@${DONATION_DB_ENDPOINT}/donationdb" \
  --from-literal=AWS_SQS_URL="${SQS_QUEUE_URL}" \
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
# Pré-requisito: endpoints dinâmicos devem estar exportados.
# Execute no diretório infra/terraform/ ANTES destes comandos:
#   export NGO_DB_ENDPOINT=$(terraform output -raw ngo_db_endpoint)
#   export DONATION_DB_ENDPOINT=$(terraform output -raw donation_db_endpoint)

# ngo-db — cria tabela ngos e insere seeds
kubectl run psql-ngo --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_ngo_db_password}" \
  -- psql -h "$(echo $NGO_DB_ENDPOINT | cut -d: -f1)" \
         -U solidarytech -d ngodb \
         -c "$(cat ~/FIAP/Fase5/solidarytech-ngo/db/init.sql)"

# donation-db — cria tabela donations
kubectl run psql-donation --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_donation_db_password}" \
  -- psql -h "$(echo $DONATION_DB_ENDPOINT | cut -d: -f1)" \
         -U solidarytech -d donationdb \
         -c "$(cat ~/FIAP/Fase5/solidarytech-donation/db/init.sql)"

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

**Causa raiz confirmada (via `helm template` + inspeção de `templates/datasources.yaml`):**

O template do loki-stack 2.10.2, linhas críticas:
```
{{- if .Values.grafana.sidecar.datasources.label }}
{{ label }}: {{ labelValue | quote }}
{{- else }}
grafana_datasource: "1"          ← label padrão quando label não definido
{{- end }}
```

- `grafana.sidecar.datasources.enabled: false` (boolean via `helm.values`) **deveria** impedir a criação do ConfigMap, mas testes no cluster mostraram que o ArgoCD recria o ConfigMap a cada sync, ignorando o valor boolean no bloco de values.
- `loki.isDefault: false` também funciona localmente via `helm template`, mas o cluster mantinha `isDefault: true` após hard refresh — problema de sincronização do ArgoCD com o chart Helm.
- Ambas as abordagens são não-confiáveis porque dependem de boolean false sendo passado corretamente pelo ArgoCD ao Helm.

**Solução definitiva aplicada — label spoofing:**

O chart **sempre cria** o ConfigMap `loki-loki-stack`. Em vez de impedir a criação (não-confiável), mudamos o label que ele usa:

```
grafana.sidecar.datasources.label: "loki_ds_disabled"
```

Resultado via `helm template` (confirmado):
```
labels:
  loki_ds_disabled: "1"   ← não é mais "grafana_datasource: 1"
```

O Grafana sidecar do kube-prometheus-stack procura `grafana_datasource: "1"` → **não encontra** `loki-loki-stack` → ignora.
Nosso `gitops/monitoring/loki-datasource.yaml` mantém `grafana_datasource: "1"` e `isDefault: false` → Grafana registra Loki corretamente.

**Para aplicar no cluster (primeira vez ou após recriar):**

```bash
# 1. Hard refresh do ArgoCD (propaga o novo label no loki-application.yaml):
kubectl annotate application loki -n argocd argocd.argoproj.io/refresh=hard --overwrite

# 2. Verificar que o ConfigMap do chart agora usa o label errado (invisível ao Grafana):
kubectl get configmap loki-loki-stack -n monitoring -o yaml | grep -E "loki_ds_disabled|grafana_datasource"
# Esperado: loki_ds_disabled: "1"  (e NÃO grafana_datasource: "1")

# 3. Verificar que nosso ConfigMap existe com o label correto:
kubectl get configmap loki-datasource -n monitoring -o yaml | grep -E "grafana_datasource|isDefault"
# Esperado: grafana_datasource: "1"  e  isDefault: false

# 4. Se o monitoring-config Application ainda não existir no ArgoCD:
kubectl apply -f solidarytech-infra/gitops/argocd/monitoring-application.yaml

# 5. Reiniciar Grafana para recarregar datasources:
kubectl rollout restart deployment prometheus-grafana -n monitoring

# 6. Verificar datasources no Grafana UI:
#    Configuration → Data Sources → Prometheus (default) + Loki (não default)
```

---

## 12. Retorno de Sessão — Subindo o Ambiente do Zero

Procedimento completo para resubir o ambiente após `terraform destroy` ou expiração de sessão.
Executar **na ordem exata**. Tempo estimado: 25–35 minutos até todos os pods Running.

---

### Passo 1 — Renovar credenciais AWS Academy

1. Acesse [https://awsacademy.instructure.com](https://awsacademy.instructure.com) → seu curso → **Módulos** → **Learner Lab** → **Start Lab**
2. Clique em **AWS Details** → **AWS CLI** → copie as três variáveis
3. Cole no terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Verificar conta correta:
aws sts get-caller-identity
# Esperado: "Account": "354132155257"
```

---

### Passo 2 — Atualizar Secrets do GitHub (pipelines CI/CD)

Necessário para que as pipelines GitHub Actions consigam fazer push no ECR e atualizar o GitOps.

Nos três repositórios (`solidarytech-ngo`, `solidarytech-donation`, `solidarytech-volunteer`):
**Settings → Secrets and variables → Actions → atualizar os três secrets:**

```
AWS_ACCESS_KEY_ID      ← valor de $AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY  ← valor de $AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN      ← valor de $AWS_SESSION_TOKEN
```

> Dica: use a GitHub CLI para atualizar os 3 repos rapidamente:
> ```bash
> for REPO in solidarytech-ngo solidarytech-donation solidarytech-volunteer; do
>   gh secret set AWS_ACCESS_KEY_ID     --body "$AWS_ACCESS_KEY_ID"     -R "Pereira277/$REPO"
>   gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY" -R "Pereira277/$REPO"
>   gh secret set AWS_SESSION_TOKEN     --body "$AWS_SESSION_TOKEN"     -R "Pereira277/$REPO"
> done
> ```

> **Cenário: cluster ainda rodando (sessão de curta duração — sem terraform destroy)**
> Se o cluster EKS está de pé e você só renovou as credenciais AWS Academy, o
> `volunteer-service-secret` precisa ser recriado com o novo `AWS_SESSION_TOKEN`:
> ```bash
> kubectl delete secret volunteer-service-secret -n solidarytech
> kubectl create secret generic volunteer-service-secret \
>   --namespace solidarytech \
>   --from-literal=AWS_DYNAMODB_TABLE="solidarytech-volunteers" \
>   --from-literal=AWS_REGION="us-east-1" \
>   --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
>   --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
>   --from-literal=AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}"
> kubectl rollout restart deployment volunteer-service -n solidarytech
> ```
> Neste cenário, pular para os passos 4 (kubectl) e aplicar apenas o que for necessário.

---

### Passo 3 — Exportar senhas e aplicar Terraform

```bash
# Definir senhas (nunca em arquivo):
export TF_VAR_ngo_db_password="<senha-forte-sem-/@-espaco>"
export TF_VAR_donation_db_password="<senha-forte-sem-/@-espaco>"

cd ~/FIAP/Fase5/solidarytech-infra/infra/terraform/

terraform init        # re-autentica backend S3 com as novas credenciais
terraform plan -out=plan.out
terraform apply plan.out

# Salvar outputs como variáveis de ambiente (endpoints mudam a cada recreate):
export NGO_DB_ENDPOINT=$(terraform output -raw ngo_db_endpoint)
export DONATION_DB_ENDPOINT=$(terraform output -raw donation_db_endpoint)
export SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url)

echo "NGO DB:      $NGO_DB_ENDPOINT"
echo "Donation DB: $DONATION_DB_ENDPOINT"
echo "SQS URL:     $SQS_QUEUE_URL"
```

---

### Passo 4 — Configurar kubectl

```bash
aws eks update-kubeconfig \
  --name solidarytech-cluster \
  --region us-east-1

kubectl get nodes
# Esperado: 2 nodes em "Ready" (pode levar 2-3 min após o apply)
```

---

### Passo 5 — Instalar ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Aguardar pods ficarem Running (~2 min):
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=300s

kubectl get pods -n argocd
# Todos devem estar Running/Completed
```

---

### Passo 6 — Criar namespaces e Secrets Kubernetes

```bash
# --- Namespace solidarytech ---
kubectl apply -f ~/FIAP/Fase5/solidarytech-infra/gitops/namespace.yaml

# --- Namespace monitoring ---
kubectl create namespace monitoring

# --- ngo-service-secret ---
kubectl create secret generic ngo-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_ngo_db_password}@${NGO_DB_ENDPOINT}/ngodb"

# --- donation-service-secret ---
kubectl create secret generic donation-service-secret \
  --namespace solidarytech \
  --from-literal=DATABASE_URL="postgresql://solidarytech:${TF_VAR_donation_db_password}@${DONATION_DB_ENDPOINT}/donationdb" \
  --from-literal=AWS_SQS_URL="${SQS_QUEUE_URL}" \
  --from-literal=AWS_REGION="us-east-1"

# --- volunteer-service-secret (credenciais AWS Academy expiram em ~4h — recriar a cada sessão) ---
kubectl create secret generic volunteer-service-secret \
  --namespace solidarytech \
  --from-literal=AWS_DYNAMODB_TABLE="solidarytech-volunteers" \
  --from-literal=AWS_REGION="us-east-1" \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}"

# --- new-relic-secret (License Key fixa — não expira com AWS Academy) ---
kubectl create secret generic new-relic-secret \
  --namespace monitoring \
  --from-literal=NEW_RELIC_LICENSE_KEY="<sua-license-key-new-relic>"

# Verificar todos os secrets:
kubectl get secrets -n solidarytech
kubectl get secrets -n monitoring
```

> **AVISO — volunteer-service:** O `AWS_SESSION_TOKEN` expira em ~4h com o AWS Academy.
> A cada nova sessão recriar o secret e fazer restart do deployment:
> ```bash
> kubectl delete secret volunteer-service-secret -n solidarytech
> kubectl create secret generic volunteer-service-secret --namespace solidarytech \
>   --from-literal=AWS_DYNAMODB_TABLE="solidarytech-volunteers" \
>   --from-literal=AWS_REGION="us-east-1" \
>   --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
>   --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
>   --from-literal=AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}"
> kubectl rollout restart deployment volunteer-service -n solidarytech
> ```

---

### Passo 7 — Aplicar CRD do Prometheus via server-side (OBRIGATÓRIO)

O CRD `prometheuses.monitoring.coreos.com` excede o limite de annotations do etcd.
O apply client-side padrão do ArgoCD falha nesse CRD. Aplicar antes das Applications:

```bash
kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.71.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml

# Verificar que o CRD foi registrado:
kubectl get crd prometheuses.monitoring.coreos.com
```

---

### Passo 8 — Restart do operador do Prometheus (obrigatório após CRD)

O operador é implantado pelo kube-prometheus-stack (passo seguinte). Se o cluster já tiver
o operador rodando de uma sessão anterior, reiniciá-lo agora garante que ele reconhece o CRD
recém-aplicado. Se o operador ainda não existir (primeira vez), repetir este passo após o
Passo 9 quando o ArgoCD terminar de sincronizar o kube-prometheus-stack.

```bash
kubectl rollout restart deployment prometheus-grafana-kube-pr-operator -n monitoring
kubectl rollout status deployment prometheus-grafana-kube-pr-operator -n monitoring
sleep 60
kubectl get prometheus -n monitoring
# RECONCILED e AVAILABLE devem estar True antes de continuar
```

---

### Passo 9 — Aplicar as 7 ArgoCD Applications

```bash
cd ~/FIAP/Fase5/solidarytech-infra

# Microsserviços (namespace solidarytech):
kubectl apply -f gitops/argocd/ngo-application.yaml
kubectl apply -f gitops/argocd/donation-application.yaml
kubectl apply -f gitops/argocd/volunteer-application.yaml

# Observabilidade (namespace monitoring):
kubectl apply -f gitops/argocd/prometheus-grafana-application.yaml
kubectl apply -f gitops/argocd/loki-application.yaml
kubectl apply -f gitops/argocd/otel-collector-application.yaml
kubectl apply -f gitops/argocd/monitoring-application.yaml

# Acompanhar sync (aguardar "Synced" e "Healthy" em todos):
kubectl get applications -n argocd -w
```

> Tempo médio de sync: kube-prometheus-stack ~5 min, loki-stack ~3 min, demais <2 min.
> Se este for o primeiro deploy (operador não existia no Passo 8), repetir o Passo 8 agora.

---

### Passo 10 — Inicializar bancos de dados

Executar apenas uma vez por ciclo de vida do RDS (após terraform apply).
O RDS está em subnets privadas; os scripts rodam via pod temporário dentro do cluster.

```bash
# ngo-db — cria tabela ngos e insere seeds
kubectl run psql-ngo --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_ngo_db_password}" \
  -- psql -h "$(echo $NGO_DB_ENDPOINT | cut -d: -f1)" \
         -U solidarytech -d ngodb \
         -c "$(cat ~/FIAP/Fase5/solidarytech-ngo/db/init.sql)"

# donation-db — cria tabela donations
kubectl run psql-donation --rm -i --restart=Never \
  --namespace=solidarytech \
  --image=postgres:17 \
  --env="PGPASSWORD=${TF_VAR_donation_db_password}" \
  -- psql -h "$(echo $DONATION_DB_ENDPOINT | cut -d: -f1)" \
         -U solidarytech -d donationdb \
         -c "$(cat ~/FIAP/Fase5/solidarytech-donation/db/init.sql)"

# volunteer-service não tem init.sql — DynamoDB já criado pelo Terraform
```

---

### Passo 11 — Confirmar reconciliação do Prometheus

```bash
# Verificar se o Prometheus StatefulSet existe e está Running:
kubectl get statefulset -n monitoring
kubectl get prometheus -n monitoring
# Esperado: RECONCILED = True, AVAILABLE = True

# Se RECONCILED estiver vazio, reiniciar o operador novamente:
kubectl rollout restart deployment \
  prometheus-grafana-kube-pr-operator -n monitoring
kubectl rollout status deployment \
  prometheus-grafana-kube-pr-operator -n monitoring

# Aguardar reconciliação:
kubectl get prometheus -n monitoring -w
```

---

### Passo 12 — Validar datasource do Loki no Grafana

```bash
# Verificar que o ConfigMap do chart NÃO tem label grafana_datasource:
kubectl get configmap loki-loki-stack -n monitoring -o yaml | \
  grep -E "loki_ds_disabled|grafana_datasource"
# Esperado: loki_ds_disabled: "1"  (não grafana_datasource)

# Verificar que nosso ConfigMap existe com label e isDefault corretos:
kubectl get configmap loki-datasource -n monitoring -o yaml | \
  grep -E "grafana_datasource|isDefault"
# Esperado: grafana_datasource: "1"  e  isDefault: false

# Se necessário, reiniciar Grafana para recarregar datasources:
kubectl rollout restart deployment prometheus-grafana -n monitoring
```

---

### Passo 13 — Validar todos os pods

```bash
# Microsserviços:
kubectl get pods -n solidarytech
# Esperado: ngo-service, donation-service, volunteer-service → Running

# Observabilidade:
kubectl get pods -n monitoring
# Esperado: prometheus-*, grafana-*, loki-*, promtail-*, alertmanager-*, otel-collector-* → Running

# URL do Grafana:
kubectl get svc -n monitoring | grep grafana
# Copiar EXTERNAL-IP → http://<EXTERNAL-IP> | admin / SolidaryAdmin2024!

# Teste rápido dos endpoints dos microsserviços:
NGO_IP=$(kubectl get svc ngo-service -n solidarytech -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
         kubectl get svc ngo-service -n solidarytech -o jsonpath='{.spec.clusterIP}')
curl -s http://${NGO_IP}:8081/health
# Esperado: {"status":"ok","service":"ngo-service"}
```

---

### Resumo rápido (checklist de sessão)

```
[ ] 1.  Exportar credenciais AWS Academy  (aws sts get-caller-identity → 354132155257)
[ ] 2.  Atualizar GitHub Secrets (3 repos)
[ ] 3.  export TF_VAR_ngo_db_password + TF_VAR_donation_db_password
[ ] 4.  terraform init && terraform apply  |  salvar outputs em $NGO_DB_ENDPOINT etc.
[ ] 5.  aws eks update-kubeconfig  |  kubectl get nodes → 2 Ready
[ ] 6.  kubectl create namespace argocd + instalar ArgoCD
[ ] 7.  Criar namespaces + 4 secrets (ngo, donation, volunteer, new-relic)
[ ] 8.  kubectl apply --server-side CRD prometheuses.monitoring.coreos.com
[ ] 9.  Restart operador Prometheus (se já existir)  |  kubectl rollout restart + sleep 60
[ ] 10. kubectl apply 7 ArgoCD Applications  |  repetir passo 9 se primeiro deploy
[ ] 11. Init SQL: ngo-db + donation-db via pod temporário
[ ] 12. Confirmar RECONCILED=True no Prometheus
[ ] 13. Validar pods solidarytech e monitoring
```

---

## 13. SRE — Etapa 6: Dashboard e Documento Formal

### 13.1 Artefatos criados

| Artefato | Localização | Finalidade |
|---|---|---|
| Documento SRE formal | `docs/SRE.md` | SLI/SLO/SLA do donation-service, Error Budget, MTTR |
| Dashboard Grafana | `gitops/monitoring/sre-dashboard.yaml` | 7 painéis de Golden Metrics |
| ArgoCD Application | `gitops/argocd/monitoring-application.yaml` | Gerencia tudo em `gitops/monitoring/` |

### 13.2 Como Acessar o Dashboard SRE no Grafana

```bash
# 1. Obter o External IP do Grafana:
kubectl get svc -n monitoring | grep grafana

# 2. Acessar no browser:
#    http://<EXTERNAL-IP>
#    Usuário: admin | Senha: SolidaryAdmin2024!

# 3. Navegar até o dashboard:
#    Dashboards → Browse → "SolidaryTech — SRE Dashboard (donation-service)"
#    OU usar a busca: Ctrl+K → "SRE"

# 4. Verificar que o dashboard foi carregado pelo sidecar:
kubectl get configmap sre-dashboard -n monitoring
# Esperado: sre-dashboard   1      <algum tempo>

kubectl get configmap sre-dashboard -n monitoring -o yaml | grep grafana_dashboard
# Esperado: grafana_dashboard: "1"
```

### 13.3 Painéis do Dashboard SRE

> **Nota:** O `donation-service` não expõe `/metrics`. Os painéis usam métricas de infraestrutura
> do kube-state-metrics e cadvisor como proxy. Para SLIs de latência e erros HTTP, usar o **New Relic APM**.

| # | Painel | Tipo | Query base | Limiar |
|---|---|---|---|---|
| 1 | Disponibilidade — Pods Ready | Stat | `(count(kube_pod_status_ready{ns="solidarytech",condition="true"}) / count(kube_pod_info{ns="solidarytech"})) * 100` | < 99% → vermelho |
| 2 | Error Budget Proxy — Margem vs SLA 99,5% | Gauge | disponibilidade − 99.5 (em pp) | < 0 → vermelho (SLA violado) |
| 3 | Pod Restarts (24h) | Stat | `sum(increase(kube_pod_container_status_restarts_total{ns="solidarytech"}[24h]))` | ≥ 1 → amarelo / ≥ 5 → vermelho |
| 4 | CPU Usage — donation-service | Stat | `sum(rate(container_cpu_usage_seconds_total{pod=~"donation-service.*"}[5m])) * 1000` (millicores) | ≥ 100m → amarelo / ≥ 400m → vermelho |
| 5 | CPU timeseries — donation-service | Timeseries | idem painel 4 | Linhas: request 100m (amarelo), limit 400m (vermelho) |
| 6 | Memória timeseries — donation-service | Timeseries | `sum(container_memory_working_set_bytes{pod=~"donation-service.*"})` | Linhas: request 128Mi (amarelo), limit ~240Mi (vermelho) |
| 7 | Pods Disponíveis por Deployment | Timeseries | `kube_deployment_status_replicas_available{ns="solidarytech"}` por `{{deployment}}` | Queda = pod não-Ready |

### 13.4 Forçar re-sync do dashboard (se não aparecer no Grafana)

```bash
# O sidecar do Grafana detecta novos ConfigMaps com label grafana_dashboard="1"
# automaticamente. Se o dashboard não aparecer em ~2 min:

# Verificar que o monitoring-config Application está Synced:
kubectl get application monitoring-config -n argocd

# Se OutOfSync, forçar sync:
kubectl annotate application monitoring-config -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Reiniciar o sidecar do Grafana para re-escanear ConfigMaps:
kubectl rollout restart deployment prometheus-grafana -n monitoring
kubectl rollout status deployment prometheus-grafana -n monitoring
```

---

## 14. FinOps — Etapa 7: Tags, Rightsizing e Forecast de Custos

### 14.1 Artefatos criados

| Artefato | Localização | Finalidade |
|---|---|---|
| Documento FinOps formal | `docs/FINOPS.md` | Estratégia de tagging, rightsizing, forecast de custos, recomendações |
| Rightsizing dos deployments | `gitops/*/{ngo,donation,volunteer}-deployment.yaml` | `requests`/`limits` ajustados com base no consumo real observado no Grafana |

### 14.2 Como verificar tags aplicadas nos recursos via AWS CLI

```bash
# EKS Cluster
aws eks describe-cluster --name solidarytech-cluster --region us-east-1 \
  --query 'cluster.tags'

# RDS (ngo-db e donation-db) — describe-db-instances não retorna tags diretamente;
# usar list-tags-for-resource com o ARN da instância:
NGO_DB_ARN=$(aws rds describe-db-instances --region us-east-1 \
  --db-instance-identifier solidarytech-ngo-db \
  --query 'DBInstances[0].DBInstanceArn' --output text)
aws rds list-tags-for-resource --resource-name "$NGO_DB_ARN" --region us-east-1

# VPC
VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 \
  --filters "Name=tag:Name,Values=solidarytech-vpc" \
  --query 'Vpcs[0].VpcId' --output text)
aws ec2 describe-tags --region us-east-1 \
  --filters "Name=resource-id,Values=$VPC_ID"

# SQS
aws sqs list-queue-tags --region us-east-1 \
  --queue-url "$(aws sqs get-queue-url --queue-name solidarytech-donation-events --region us-east-1 --query QueueUrl --output text)"

# DynamoDB
TABLE_ARN=$(aws dynamodb describe-table --table-name solidarytech-volunteers --region us-east-1 \
  --query 'Table.TableArn' --output text)
aws dynamodb list-tags-of-resource --resource-arn "$TABLE_ARN" --region us-east-1

# S3 (Velero)
aws s3api get-bucket-tagging --bucket solidarytech-velero-354132155257 --region us-east-2

# ECR
aws ecr list-tags-for-resource --region us-east-1 \
  --resource-arn "$(aws ecr describe-repositories --repository-names solidarytech-donation --region us-east-1 --query 'repositories[0].repositoryArn' --output text)"
```

Todos os comandos acima devem retornar as 4 tags obrigatórias: `Project=SolidaryTech`,
`Environment=production`, `Owner=lucas`, `CostCenter=NGO-Core`.

### 14.3 Como consultar o Cost Explorer no console AWS

1. Acesse o console AWS → busque **"Cost Explorer"** (ou **"Cost Management"**)
2. **Cost Explorer** → **Launch Cost Explorer**
3. Ajustar filtros:
   - **Date range:** período da sessão ativa do AWS Academy
   - **Group by:** `Tag` → selecionar `Project` (ou `CostCenter`) para ver o gasto agrupado pela SolidaryTech
   - **Filter:** `Tag: Project = SolidaryTech` para isolar apenas os recursos do projeto
4. Alternar a visualização entre **Daily** e **Monthly** para acompanhar a curva de gasto
5. **Forecast** (aba lateral): requer histórico mínimo de dados de faturamento — no AWS
   Academy, como o ambiente é recriado a cada sessão, o Forecast automático não é
   confiável (ver nota metodológica em `docs/FINOPS.md`, seção 3.1). Usar o forecast
   manual documentado no FINOPS.md como referência.

---

_Seções adicionais serão acrescentadas conforme cada componente for criado (Etapas 8–9)._
