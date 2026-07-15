# FINOPS.md — SolidaryTech: Otimização Financeira e Tagueamento

> Documento formal de FinOps — Frente 2 do Hackathon POSTECH Fase 5 (DCLT).
> Responsável técnico: Lucas Pereira — Turma POSTECH 2026.

---

## 1. Estratégia de Tagging

### 1.1 Contexto

FinOps começa por visibilidade de custo: sem tags consistentes em todos os recursos,
não é possível atribuir gasto a projeto, ambiente ou centro de custo, nem gerar
relatórios confiáveis no AWS Cost Explorer. A SolidaryTech adota 4 tags obrigatórias,
aplicadas via `merge()` em 100% dos recursos Terraform do projeto.

### 1.2 Decisão: 4 tags obrigatórias

| Tag | Valor | Finalidade |
|---|---|---|
| `Project` | `SolidaryTech` | Agrupar todo custo da plataforma em relatórios multi-projeto |
| `Environment` | `production` | Distinguir ambiente produtivo de eventuais ambientes de teste futuros |
| `Owner` | `lucas` | Responsável técnico pelo recurso — rastreabilidade e contato |
| `CostCenter` | `NGO-Core` | Centro de custo para alocação financeira — permite fatiar custo por área de negócio |

### 1.3 Como operacionalizar

As tags são definidas uma única vez em `local.common_tags` e aplicadas a todo recurso
via `merge(local.common_tags, { Name = "..." })`, garantindo consistência e eliminando
divergência manual entre recursos:

```hcl
locals {
  common_tags = {
    Project     = "SolidaryTech"
    Environment = var.environment
    Owner       = "lucas"
    CostCenter  = "NGO-Core"
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpc"
  })
}
```

Esse padrão é replicado em `solidarytech-infra/infra/terraform/main.tf`,
`solidarytech-infra/bootstrap-s3/main.tf` e `solidarytech-infra/bootstrap-ecr/main.tf`.

### 1.4 Recursos tagueados (evidência)

Todo recurso a seguir carrega as 4 tags obrigatórias via `merge(local.common_tags, {...})`:

| Categoria | Recursos |
|---|---|
| Rede | VPC, subnets (public a/b, private a/b, db a/b), Internet Gateway, NAT Gateway + EIP, Route Tables |
| Segurança | Security Group (EKS cluster), Security Group (RDS) |
| Compute | EKS Cluster, EKS Node Group |
| Dados | RDS `ngo-db`, RDS `donation-db`, SQS `donation-events`, DynamoDB `volunteers` |
| Armazenamento | S3 `velero` (backup DR), S3 `terraform-state` (bootstrap-s3) |
| Registro de imagens | ECR `solidarytech-ngo`, `solidarytech-donation`, `solidarytech-volunteer` (bootstrap-ecr) |

**Verificação:** `terraform plan` não acusa diffs de tag em nenhum dos 3 módulos
(`bootstrap-s3`, `bootstrap-ecr`, `infra/terraform`) — confirmando 100% de cobertura.
Procedimento de auditoria via AWS CLI documentado em `docs/RUNBOOK.md`, seção "Etapa 7 — FinOps".

---

## 2. Análise de Rightsizing

### 2.1 Contexto

Os 3 microsserviços foram provisionados na Etapa 2 com `requests`/`limits` herdados do
padrão de fases anteriores (`cpu: 500m`, `memory: 256Mi`), sem dados reais de consumo.
Após a Etapa 6 (SRE), o dashboard Grafana expõe consumo real de CPU e memória via
`container_cpu_usage_seconds_total` e `container_memory_working_set_bytes`. Esses dados
permitem substituir a estimativa inicial por um dimensionamento baseado em evidência.

### 2.2 Dados observados (dashboard Grafana — SRE)

| Serviço | CPU observada (pico) | Memória observada (pico) | Limits atuais |
|---|---|---|---|
| `donation-service` | ~0,0325 millicores | ~3,94 MiB | cpu: 500m / memory: 256Mi |
| `ngo-service` | ~0,119 millicores | ~50,9 MiB | cpu: 500m / memory: 256Mi |
| `volunteer-service` | ~0,123 millicores | ~85,1 MiB | cpu: 500m / memory: 256Mi |

Os três serviços operam com carga mínima no ambiente do AWS Academy (tráfego de
validação manual, sem carga de produção real), o que evidencia superdimensionamento
severo: os `limits` atuais chegam a ser **milhares de vezes** maiores que o pico
observado de CPU.

### 2.3 Metodologia de ajuste

Aplicou-se margem de segurança de **3x sobre o pico observado**, arredondando para
valores práticos de Kubernetes (múltiplos de `10m` para CPU e potências convenientes
de memória), com piso mínimo que garanta partida estável do runtime (Go/Python) mesmo
sob picos de latência.

| Serviço | CPU pico × 3 | CPU ajustada (request/limit) | Memória pico × 3 | Memória ajustada (request/limit) |
|---|---|---|---|---|
| `donation-service` | ~0,0975 millicores | **10m / 100m** | ~11,8 MiB | **32Mi / 64Mi** |
| `ngo-service` | ~0,357 millicores | **10m / 200m** | ~152,7 MiB | **64Mi / 128Mi** |
| `volunteer-service` | ~0,369 millicores | **10m / 200m** | ~255,3 MiB | **96Mi / 192Mi** |

> **Nota:** o piso de `10m` de CPU é aplicado a todos os serviços porque o pico real
> observado (< 0,15 millicores) é ordens de grandeza menor que qualquer valor prático
> de `request`; `10m` é o menor valor operacionalmente razoável no EKS e ainda assim
> representa uma redução de 98% frente ao `request` anterior de `100m`. Para memória,
> o ajuste segue a margem de 3x diretamente, com folga adicional em `ngo-service` e
> `volunteer-service` por serem os processos com maior pegada de runtime (Flask + libs).

### 2.4 Impacto

Reduzir `limits` de CPU de `500m` para `100m`–`200m` por serviço libera capacidade
alocável no node group, permitindo mais pods por nó sem aumentar o número de nodes —
o principal driver de custo em EKS (Seção 4 trata otimização adicional via Karpenter).

---

## 3. Forecast de Custos Mensais

### 3.1 Nota metodológica — por que o cálculo é manual

O AWS Academy recria o ambiente (conta, VPC, cluster, bancos) a cada sessão de estudo:
os recursos são destruídos ao final da sessão para economizar o crédito de US$50 e
recriados na sessão seguinte. Isso impede o acúmulo de histórico de uso contínuo no
**AWS Cost Explorer**, que depende de dias/semanas de dados de faturamento reais para
gerar forecast automático confiável. Por esse motivo, o forecast abaixo foi calculado
manualmente com base nos **preços públicos da AWS (julho de 2026, região us-east-1)**
aplicados à topologia de recursos definida em `infra/terraform/main.tf`, representando
o custo projetado caso um ambiente equivalente rodasse **24/7 em produção real**
(fora do regime efêmero do AWS Academy).

### 3.2 Premissas de precificação

- Região: us-east-1 (N. Virginia)
- Regime: 730 horas/mês (24/7)
- On-Demand, sem Reserved Instances / Savings Plans (ver Seção 4 para otimizações)

### 3.3 Breakdown por serviço

| Item | Cálculo | Custo mensal (US$) | % do total |
|---|---|---|---|
| EKS cluster (control plane) | $0,10/h × 730h | $73,00 | 37,6% |
| EC2 — 2× t3.medium (node group, On-Demand) | 2 × $0,0416/h × 730h | $60,00 | 30,9% |
| RDS — 2× db.t3.micro PostgreSQL (Single-AZ) | 2 × $0,017/h × 730h | $25,00 | 12,9% |
| NAT Gateway | $0,045/h × 730h + $0,045/GB | $33,00 | 17,0% |
| SQS Standard (`donation-events`) | < 1M requests/mês (tier gratuito) | $0,40 | 0,2% |
| DynamoDB (`volunteers`, PAY_PER_REQUEST) | uso atual mínimo | $1,00 | 0,5% |
| S3 (state + Velero) | uso atual mínimo | $1,00 | 0,5% |
| ECR (3 repositórios) | uso atual mínimo | $1,00 | 0,5% |
| **Total estimado** | | **$194,40** | **100%** |

### 3.4 Leitura do resultado

Compute (EKS control plane + EC2 node group) responde por **~68%** do custo total —
o alvo prioritário de otimização. NAT Gateway isolado já supera o custo combinado de
SQS + DynamoDB + S3 + ECR, o que o torna o segundo maior alvo de revisão arquitetural
(Seção 4).

---

## 4. Recomendações de Otimização Nativa de Nuvem

1. **EKS com Karpenter para autoscaling de nodes** — substitui o node group fixo
   (2× t3.medium sempre ativos) por provisionamento sob demanda baseado em pods
   pendentes, eliminando nodes ociosos fora de pico. Com o rightsizing da Seção 2,
   a carga real dos 3 microsserviços cabe com folga em capacidade bem menor que a
   provisionada hoje.

2. **RDS Aurora Serverless v2** — paga por ACU (Aurora Capacity Unit) consumida,
   escalando a zero-próximo em ociosidade. Ideal para uma ONG cuja receita e volume
   de doações variam por campanha (picos sazonais como Natal), evitando pagar por
   capacidade de banco dimensionada para o pico o mês inteiro.

3. **Savings Plans de 1 ano para EC2** — compromisso de uso do node group do EKS
   com desconto de ~30% frente a On-Demand, sem exigir mudança de instância ou
   arquitetura. Baixo risco: a carga de compute (EKS) é previsível e contínua.

4. **NAT Gateway consolidado em única AZ para ambiente de desenvolvimento** — hoje
   já há apenas 1 NAT Gateway (em `public_a`), já otimizado para o ambiente único do
   hackathon; a recomendação vale como princípio a manter caso o ambiente evolua
   para multi-AZ redundante — não duplicar NAT Gateway por AZ sem necessidade real
   de alta disponibilidade de rede.

5. **S3 Intelligent-Tiering para backups Velero antigos** — move automaticamente
   objetos de backup pouco acessados para camadas de custo menor sem exigir
   lifecycle policies manuais, reduzindo custo de armazenamento à medida que o
   histórico de backups cresce.

---

## 5. Conclusão

| Cenário | Custo mensal projetado | Variação |
|---|---|---|
| Atual (On-Demand, sem otimizações) | ~$194/mês | baseline |
| Otimizado (Savings Plans EC2 + Aurora Serverless v2) | ~$120/mês | **~38% de redução** |

Para uma organização sem fins lucrativos como a SolidaryTech, cada dólar economizado em
infraestrutura é um dólar adicional disponível para repasse às ONGs parceiras ou para
expansão da plataforma. Uma redução de ~38% no custo de operação — sem perda de
disponibilidade ou desempenho, apoiada em compromisso de uso previsível (Savings Plans)
e em capacidade de banco elástica (Aurora Serverless v2) — é, portanto, uma prioridade
estratégica e não apenas uma otimização técnica incremental.

---

_Documento correspondente à Etapa 7 (FinOps) do CONTEXT.md, seção 6. Ver também
`docs/RUNBOOK.md`, seção "Etapa 7 — FinOps", para procedimentos operacionais de
verificação de tags e consulta ao Cost Explorer._
