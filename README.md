# Infra-ecs

Infraestrutura do cluster ECS do projeto **nexTime-frame**, provisionada com Terraform na AWS. Este repositório define o cluster ECS Fargate, as definições de tarefa (padrão de 3 containers com observabilidade Datadog), os serviços, o ALB interno, as IAM roles, o autoscaling e os security groups.

## Sumário

- [Visão Geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Recursos Provisionados](#recursos-provisionados)
- [Padrão de 3 Containers](#padrão-de-3-containers)
- [Pré-requisitos](#pré-requisitos)
- [Variáveis](#variáveis)
- [Outputs](#outputs)
- [Como Usar](#como-usar)
- [Backend Remoto](#backend-remoto)
- [CI/CD](#cicd)
- [Ordem de Deploy](#ordem-de-deploy)
- [Contribuição](#contribuição)

---

## Visão Geral

O `Infra-ecs` é o **quarto stack a ser aplicado** na ordem de deploy. Ele depende dos outputs do `infra-core` (VPC, subnets, security groups, ECR URLs, Secrets Manager ARNs) e do `infra-messaging` (SQS, S3).

> **Atenção**: após **cada** `terraform apply` neste repositório, o stack `infra-gateway` **deve ser reaplicado imediatamente**. O ARN do ALB Listener muda a cada apply e o API Gateway mantém referência a esse ARN. Não reaplicar o `infra-gateway` causa erros 500 em todas as rotas.

---

## Arquitetura

```
API Gateway (HTTP v2)
      │ VPC Link
      ▼
Internal ALB  (port 80, subnets privadas)
      │
      ▼
ECS Service: ms-video   (FARGATE_SPOT, port 8090)
      │
      └── [Fluent Bit] → Datadog Logs
      └── [Datadog Agent] → Métricas + APM (port 8126)
      └── [ms-video app] → -javaagent:/dd-java-agent.jar

ECS Service: process-video  (FARGATE_SPOT, port 8080)
      └── [Fluent Bit] → Datadog Logs
      └── [Datadog Agent] → Métricas + APM
      └── [process-video app] → -javaagent:/dd-java-agent.jar
```

---

## Recursos Provisionados

### ECS

| Recurso | Nome | Descrição |
|---|---|---|
| `aws_ecs_cluster` | `nextime-frame-cluster` | Cluster com Container Insights habilitado |
| `aws_ecs_cluster_capacity_providers` | — | Capacidade exclusiva `FARGATE_SPOT` |
| `aws_ecs_task_definition` | `nextime-frame-ms-video` | Task definition do ms-video (3 containers) |
| `aws_ecs_task_definition` | `nextime-frame-process-video` | Task definition do process-video (3 containers) |
| `aws_ecs_service` | `nextime-frame-ms-video-service` | Serviço ECS do ms-video |
| `aws_ecs_service` | `nextime-frame-process-video-service` | Serviço ECS do process-video |

### ALB

| Recurso | Nome | Descrição |
|---|---|---|
| `aws_lb` | `nextime-frame-internal-alb` | ALB interno nas subnets privadas |
| `aws_lb_target_group` | `nextime-frame-ms-video-tg` | Target group para ms-video (port 8090, health: `/actuator/health`) |
| `aws_lb_listener` | HTTP :80 | Listener HTTP que encaminha para o target group do ms-video |

### Security Groups

| Security Group | Regras de Entrada | Destino |
|---|---|---|
| `nextime-frame-alb-sg` | TCP 80 de `10.0.0.0/8` | ALB interno — aceita tráfego do VPC Link |
| `nextime-frame-ecs-app-sg` | TCP 8090 do ALB SG | ECS tasks ms-video |
| `nextime-frame-ecs-app-sg` | TCP 8080 do ALB SG | ECS tasks process-video |

### IAM

| Role | Uso |
|---|---|
| **Execution Role** | Permite que o ECS agent faça pull de imagem no ECR e leia segredos do Secrets Manager (Mongo URI, Datadog API Key) |
| **Task Role** | Permissões de runtime das tasks: SQS (`SendMessage`, `ReceiveMessage`, `DeleteMessage`), S3 (`GetObject`, `PutObject`), Cognito (`AdminGetUser`), SES (`SendEmail`), CloudWatch Logs |

### Autoscaling

Ambos os serviços usam **Target Tracking Scaling** baseado em CPU:

| Parâmetro | Valor |
|---|---|
| Mínimo de tasks | 1 |
| Máximo de tasks | 2 |
| Alvo de CPU | 70% |
| Cooldown scale-out | 60 s |
| Cooldown scale-in | 300 s |

---

## Padrão de 3 Containers

Cada task definition inclui os seguintes containers, nesta ordem de dependência:

### 1. `log_router` (Fluent Bit / FireLens)

- Imagem: `amazon/aws-for-fluent-bit:stable`
- Função: roteador de logs via FireLens — coleta logs do container da aplicação e os encaminha ao Datadog
- `essential: true`

### 2. `datadog-agent`

- Imagem: `public.ecr.aws/datadog/agent:latest`
- Porta: `8126` (APM traces)
- Variáveis importantes: `DD_API_KEY` (lida do Secrets Manager), `DD_SITE=datadoghq.com`, `ECS_FARGATE=true`
- Criado condicionalmente: somente quando `local.datadog_enabled` for `true` (ARN do segredo Datadog não-vazio)
- Quando desabilitado, os logs da aplicação vão para CloudWatch

### 3. Container da aplicação (`ms-video` ou `process-video`)

- ENTRYPOINT inclui `-javaagent:/dd-java-agent.jar`
- `DD_AGENT_HOST=127.0.0.1` (sidecar na mesma task)
- `DD_SERVICE`, `DD_ENV`, `DD_VERSION` configurados via variáveis de ambiente
- `dependsOn: log_router (START), datadog-agent (START)`

---

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configurado
- Estado remoto do `infra-core` disponível em `nextime-frame-state-bucket-s3`
- Imagens Docker do `ms-video` e `process-video` publicadas no ECR

---

## Variáveis

| Variável | Tipo | Descrição | Padrão |
|---|---|---|---|
| `project_name` | `string` | Prefixo de todos os recursos | `nextime-frame` |
| `region` | `string` | Região AWS | `us-east-1` |
| `ms_video_port` | `number` | Porta da task ms-video | `8090` |
| `process_video_port` | `number` | Porta da task process-video | `8080` |
| `ms_video_image` | `string` | URI da imagem ECR do ms-video | — |
| `process_video_image` | `string` | URI da imagem ECR do process-video | — |
| `tags` | `map(string)` | Tags aplicadas a todos os recursos | `{ Owner = "nexTime-frame" }` |

---

## Outputs

Lidos pelo `infra-gateway` e demais stacks via `terraform_remote_state`:

| Output | Descrição |
|---|---|
| `ecs_cluster_name` | Nome do cluster ECS |
| `ecs_cluster_arn` | ARN do cluster ECS |
| `alb_dns_name` | DNS do ALB interno (usado pelo VPC Link do API Gateway) |
| `alb_arn` | ARN do ALB |
| `alb_listener_arn` | ARN do Listener HTTP :80 — **muda a cada apply; acione re-apply do `infra-gateway`** |
| `ms_video_service_name` | Nome do serviço ECS do ms-video |
| `process_video_service_name` | Nome do serviço ECS do process-video |
| `ms_video_target_group_arn` | ARN do target group do ms-video |

---

## Como Usar

```bash
cd Infra-ecs/infra

# Inicializar
terraform init

# Validar
terraform validate

# Plano
terraform plan

# Aplicar
terraform apply

# IMPORTANTE: após o apply, reaplicar o infra-gateway
cd ../../infra-gateway/infra
terraform apply
```

---

## Backend Remoto

```hcl
backend "s3" {
  bucket  = "nextime-frame-state-bucket-s3"
  key     = "infra-ecs/infra.tfstate"
  region  = "us-east-1"
  encrypt = true
}
```

**Data sources remotos consumidos:**

| Stack | Bucket Key | Dados utilizados |
|---|---|---|
| `infra-core` | `infra-core/infra.tfstate` | `vpc_id`, `private_subnet_ids`, `security_group_api_id`, `ms_video_ecr_url`, `process_video_ecr_url`, `docdb_secret_arn`, `datadog_api_key_secret_arn` |

---

## CI/CD

O pipeline `.github/workflows/cd-infra.yml` é acionado em push para `main`.

| Etapa | Comando |
|---|---|
| Configure AWS | OIDC via `AWS_ROLE_ARN` |
| Init | `terraform init` |
| Validate | `terraform validate` |
| Plan | `terraform plan` |
| Apply | `terraform apply -auto-approve` |

**Secrets do GitHub necessários:**

| Secret | Descrição |
|---|---|
| `AWS_ACCOUNT_ID` | ID da conta AWS |
| `AWS_ROLE_ARN` | ARN da role com permissões de deploy |

---

## Ordem de Deploy

```
1. infra-core
2. infra-messaging
3. infra-gateway
4. Infra-ecs          ← este repositório
   └── ⚠️  Sempre reaplicar infra-gateway após este step
5. lambda-sender
```

---

## Estrutura do Projeto

```
Infra-ecs/
├── infra/
│   ├── main.tf              # ECS cluster, serviços, task definitions
│   ├── variables.tf         # Declaração de variáveis
│   ├── outputs.tf           # Outputs exportados
│   ├── providers.tf         # Provider AWS + backend S3
│   ├── iam.tf               # Execution role + Task role
│   ├── alb.tf               # ALB interno, target group, listener
│   ├── autoscaling.tf       # Application Auto Scaling (CPU tracking)
│   └── security_groups.tf   # SGs do ALB e das ECS tasks
└── README.md
```

---

## Contribuição

Este repositório faz parte do hackathon FIAP — nexTime-frame. Siga o padrão de commits convencional (`feat:`, `fix:`, `docs:`, `chore:`) e mantenha a estrutura modular do Terraform.
