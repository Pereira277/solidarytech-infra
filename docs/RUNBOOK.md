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

_Seções adicionais serão acrescentadas conforme cada componente for criado (Etapas 3–9)._
