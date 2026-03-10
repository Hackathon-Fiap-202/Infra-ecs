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

  # SQS URLs constructed from account/region — no hardcoding in tfvars
  sqs_base                      = "https://sqs.${var.aws_region}.amazonaws.com/${var.aws_account_id}"
  sqs_video_process_command_url = "${local.sqs_base}/video-process-command"
  sqs_video_updated_event_url   = "${local.sqs_base}/video-updated-event"
  sqs_video_processed_event_url = "${local.sqs_base}/video-processed-event"
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
resource "aws_ecs_task_definition" "ms_video" {
  family                   = "ms-video"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "ms-video"
      image     = "${local.ms_video_ecr_url}:${var.image_tag}"
      essential = true

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
        { name = "SPRING_CLOUD_SQS_QUEUES_VIDEO_UPDATED_EVENT", value = "video-updated-event" }
      ]

      secrets = [
        {
          name      = "MONGO_URI"
          valueFrom = "${local.docdb_secret_arn}:mongo_uri::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ms_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
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
resource "aws_ecs_task_definition" "process_video" {
  family                   = "process-video"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "process-video"
      image     = "${local.process_video_ecr_url}:${var.image_tag}"
      essential = true

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
        { name = "APP_BUCKETS_VIDEO_PROCESSED_PREFIX", value = var.s3_processed_prefix }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.process_video.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
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
