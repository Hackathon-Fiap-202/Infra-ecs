# ─── ECS Task Execution Role ──────────────────────────────────────────────────
# Used by ECS agent to pull ECR images and push logs to CloudWatch
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow pulling Secrets Manager secrets (for DocDB credentials and Datadog API key)
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.project_name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = compact([
          local.docdb_secret_arn,
          # Datadog API key — only included when the secret ARN is known
          local.datadog_enabled ? local.datadog_api_key_secret_arn : ""
        ])
      }
    ]
  })
}

# ─── ECS Task Role ────────────────────────────────────────────────────────────
# Used by the application code running inside the container
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "ecs_task_policy" {
  name        = "${var.project_name}-ecs-task-policy"
  description = "Permissions for ECS tasks: SQS, S3, Cognito, SES, Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # SQS
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          "arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:video-process-command",
          "arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:video-updated-event",
          "arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:video-processed-event"
        ]
      },
      # S3
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      # Cognito (used by ms-video to look up user emails)
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:ListUsers"
        ]
        Resource = "arn:aws:cognito-idp:${var.aws_region}:${var.aws_account_id}:userpool/*"
      },
      # SES
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      },
      # Secrets Manager (DocumentDB credentials)
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [local.docdb_secret_arn]
      },
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}
