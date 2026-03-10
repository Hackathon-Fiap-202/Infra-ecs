# ─── Remote state from infra-core ────────────────────────────────────────────
data "terraform_remote_state" "infra_core" {
  backend = "s3"
  config = {
    bucket = "nextime-frame-state-bucket-s3"
    key    = "infra-core/infra.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id                = data.terraform_remote_state.infra_core.outputs.vpc_id
  private_subnet_ids    = data.terraform_remote_state.infra_core.outputs.private_subnet_ids
  public_subnet_ids     = data.terraform_remote_state.infra_core.outputs.public_subnet_ids
  ms_video_ecr_url      = data.terraform_remote_state.infra_core.outputs.ms_video_ecr_url
  process_video_ecr_url = data.terraform_remote_state.infra_core.outputs.process_video_ecr_url
  docdb_secret_arn      = data.terraform_remote_state.infra_core.outputs.docdb_secret_arn

  # Datadog secret ARN flows in automatically from infra-core remote state —
  # no manual copy-paste or -var flag needed in this stack.
  datadog_api_key_secret_arn = data.terraform_remote_state.infra_core.outputs.datadog_api_key_secret_arn

  # SQS URLs constructed from account/region — no hardcoding in tfvars
  sqs_base                      = "https://sqs.${var.aws_region}.amazonaws.com/${var.aws_account_id}"
  sqs_video_process_command_url = "${local.sqs_base}/video-process-command"
  sqs_video_updated_event_url   = "${local.sqs_base}/video-updated-event"
  sqs_video_processed_event_url = "${local.sqs_base}/video-processed-event"
}

# ─── Datadog API Key (from infra-core remote state) ──────────────────────────
# The secret is created and managed by infra-core/modules/datadog.
# Its ARN is pulled automatically via remote state — no manual step needed.
data "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id = local.datadog_api_key_secret_arn
}

# ─── ECS Cluster ─────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }
}

# ─── CloudWatch Log Groups ───────────────────────────────────────────────────
# Used by the Datadog agent sidecar and Fluent Bit router for their own logs.
# Application logs are routed to Datadog via FireLens (awsfirelens driver).
resource "aws_cloudwatch_log_group" "ms_video" {
  name              = "/ecs/${var.project_name}/ms-video"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "process_video" {
  name              = "/ecs/${var.project_name}/process-video"
  retention_in_days = 7
  tags              = var.tags
}

# ─── Task Definition: ms-video ───────────────────────────────────────────────
# 3-container pattern: log_router (FireLens) + datadog-agent + ms-video app
resource "aws_ecs_task_definition" "ms_video" {
  family                   = "ms-video"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    # ── 1. FireLens log router ────────────────────────────────────────────────
    # Must start before the app container (app dependsOn this with START condition).
    # Routes application logs to Datadog. Its own logs go to CloudWatch.
    {
      name      = "log_router"
      image     = "amazon/aws-for-fluent-bit:stable"
      essential = true

      firelensConfiguration = {
        type = "fluentbit"
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ms_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "firelens"
        }
      }

      # Fluent Bit is lightweight — reserve minimal resources
      cpu    = 64
      memory = 128
    },

    # ── 2. Datadog Agent sidecar ──────────────────────────────────────────────
    # Collects ECS Fargate metrics and receives APM traces from the app (port 8126).
    # DD_API_KEY is injected securely from Secrets Manager at task launch.
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:latest"
      essential = true

      environment = [
        # Tell the agent it is running on ECS Fargate (enables Fargate metrics collection)
        { name = "ECS_FARGATE", value = "true" },
        # Datadog intake endpoint — change to datadoghq.eu for EU customers
        { name = "DD_SITE", value = var.dd_site },
        # Enable log collection from FireLens-routed container logs
        { name = "DD_LOGS_ENABLED", value = "true" },
        # Enable APM trace collection
        { name = "DD_APM_ENABLED", value = "true" },
        # Accept traces from other containers in the task (127.0.0.1:8126)
        { name = "DD_APM_NON_LOCAL_TRAFFIC", value = "true" },
        # Tag all telemetry with the deployment environment
        { name = "DD_ENV", value = "prod" }
      ]

      secrets = [
        {
          name      = "DD_API_KEY"
          valueFrom = local.datadog_api_key_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ms_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "datadog-agent"
        }
      }

      cpu    = 256
      memory = 512
    },

    # ── 3. Application container ──────────────────────────────────────────────
    {
      name      = "ms-video"
      image     = "${local.ms_video_ecr_url}:${var.image_tag}"
      essential = true

      # Wait for FireLens to be running before the app starts sending logs
      dependsOn = [
        { containerName = "log_router", condition = "START" }
      ]

      portMappings = [
        {
          containerPort = var.ms_video_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "SERVER_PORT", value = tostring(var.ms_video_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SPRING_CLOUD_AWS_REGION_STATIC", value = var.aws_region },
        { name = "SPRING_CLOUD_S3_BUCKET_NAME", value = var.s3_bucket_name },
        { name = "SPRING_CLOUD_S3_INPUT_PREFIX", value = var.s3_input_prefix },
        { name = "SPRING_CLOUD_SQS_QUEUES_VIDEO_PROCESS_EVENT", value = "video-processed-event" },
        { name = "SPRING_CLOUD_SQS_QUEUES_VIDEO_PROCESS_COMMAND", value = "video-process-command" },
        { name = "SPRING_CLOUD_SQS_QUEUES_VIDEO_UPDATED_EVENT", value = "video-updated-event" },
        # ── Datadog APM / Unified Service Tagging ──────────────────────────────
        # DD_AGENT_HOST points to the Datadog sidecar (same task = 127.0.0.1)
        { name = "DD_AGENT_HOST", value = "127.0.0.1" },
        { name = "DD_ENV", value = "prod" },
        { name = "DD_SERVICE", value = "ms-video" },
        { name = "DD_VERSION", value = "1.0" }
      ]

      secrets = [
        {
          name      = "MONGO_URI"
          valueFrom = "${local.docdb_secret_arn}:mongo_uri::"
        }
      ]

      # Application logs → Datadog via FireLens / Fluent Bit
      # The apikey is the plain-text secret value (FireLens options do not support
      # Secrets Manager references natively; the key is not exposed in app code).
      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name       = "datadog"
          apikey     = data.aws_secretsmanager_secret_version.datadog_api_key.secret_string
          dd_service = "ms-video"
          dd_source  = "java"
          dd_tags    = "env:prod,version:1.0"
          TLS        = "on"
          provider   = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.ms_video_port}/actuator/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = var.tags
}

# ─── Task Definition: process-video ──────────────────────────────────────────
# 3-container pattern: log_router (FireLens) + datadog-agent + process-video app
resource "aws_ecs_task_definition" "process_video" {
  family                   = "process-video"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    # ── 1. FireLens log router ────────────────────────────────────────────────
    {
      name      = "log_router"
      image     = "amazon/aws-for-fluent-bit:stable"
      essential = true

      firelensConfiguration = {
        type = "fluentbit"
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.process_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "firelens"
        }
      }

      cpu    = 64
      memory = 128
    },

    # ── 2. Datadog Agent sidecar ──────────────────────────────────────────────
    {
      name      = "datadog-agent"
      image     = "public.ecr.aws/datadog/agent:latest"
      essential = true

      environment = [
        { name = "ECS_FARGATE", value = "true" },
        { name = "DD_SITE", value = var.dd_site },
        { name = "DD_LOGS_ENABLED", value = "true" },
        { name = "DD_APM_ENABLED", value = "true" },
        { name = "DD_APM_NON_LOCAL_TRAFFIC", value = "true" },
        { name = "DD_ENV", value = "prod" }
      ]

      secrets = [
        {
          name      = "DD_API_KEY"
          valueFrom = local.datadog_api_key_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.process_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "datadog-agent"
        }
      }

      cpu    = 256
      memory = 512
    },

    # ── 3. Application container ──────────────────────────────────────────────
    {
      name      = "process-video"
      image     = "${local.process_video_ecr_url}:${var.image_tag}"
      essential = true

      dependsOn = [
        { containerName = "log_router", condition = "START" }
      ]

      portMappings = [
        {
          containerPort = var.process_video_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "SERVER_PORT", value = tostring(var.process_video_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SPRING_CLOUD_AWS_REGION_STATIC", value = var.aws_region },
        { name = "SQS_VIDEO_PROCESS_COMMAND_URL", value = local.sqs_video_process_command_url },
        { name = "SQS_VIDEO_UPDATED_EVENT_URL", value = local.sqs_video_updated_event_url },
        { name = "APP_BUCKETS_VIDEO_BUCKET_NAME", value = var.s3_bucket_name },
        { name = "APP_BUCKETS_VIDEO_INPUT_PREFIX", value = var.s3_input_prefix },
        { name = "APP_BUCKETS_VIDEO_PROCESSED_PREFIX", value = var.s3_processed_prefix },
        # ── Datadog APM / Unified Service Tagging ──────────────────────────────
        { name = "DD_AGENT_HOST", value = "127.0.0.1" },
        { name = "DD_ENV", value = "prod" },
        { name = "DD_SERVICE", value = "process-video" },
        { name = "DD_VERSION", value = "1.0" }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          Name       = "datadog"
          apikey     = data.aws_secretsmanager_secret_version.datadog_api_key.secret_string
          dd_service = "process-video"
          dd_source  = "java"
          dd_tags    = "env:prod,version:1.0"
          TLS        = "on"
          provider   = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.process_video_port}/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = var.tags
}

# ─── ECS Service: ms-video ───────────────────────────────────────────────────
resource "aws_ecs_service" "ms_video" {
  name            = "ms-video"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.ms_video.arn
  desired_count   = var.ms_video_desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks_app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ms_video.arn
    container_name   = "ms-video"
    container_port   = var.ms_video_port
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_role_policy
  ]

  health_check_grace_period_seconds = 120

  tags = var.tags

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# ─── ECS Service: process-video ──────────────────────────────────────────────
resource "aws_ecs_service" "process_video" {
  name            = "process-video"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.process_video.arn
  desired_count   = var.process_video_desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks_app.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_role_policy
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
