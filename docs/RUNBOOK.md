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

_Seções adicionais serão acrescentadas conforme cada componente for criado (Etapas 2–9)._
