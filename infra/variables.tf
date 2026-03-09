variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "nextime-frame"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ─── Networking (from infra-core remote state) ───────────────────────────────
variable "vpc_id" {
  description = "VPC ID from infra-core"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS Fargate tasks (from infra-core)"
  type        = string
}

# ─── ECR ─────────────────────────────────────────────────────────────────────
variable "ms_video_ecr_url" {
  description = "ECR URL for ms-video image"
  type        = string
}

variable "process_video_ecr_url" {
  description = "ECR URL for process-video image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# ─── DocumentDB ──────────────────────────────────────────────────────────────
variable "docdb_endpoint" {
  description = "DocumentDB cluster endpoint"
  type        = string
}

variable "docdb_secret_arn" {
  description = "Secrets Manager ARN for DocumentDB credentials"
  type        = string
}

# ─── SQS ─────────────────────────────────────────────────────────────────────
# SQS URLs are constructed dynamically in locals from var.aws_account_id + var.aws_region

# ─── S3 ──────────────────────────────────────────────────────────────────────
variable "s3_bucket_video_input" {
  description = "S3 bucket for video input"
  type        = string
  default     = "video-input-storage"
}

variable "s3_bucket_video_processed" {
  description = "S3 bucket for processed video output"
  type        = string
  default     = "video-processed-storage"
}

# ─── Application ports ───────────────────────────────────────────────────────
variable "ms_video_port" {
  description = "Port for ms-video service"
  type        = number
  default     = 8090
}

variable "process_video_port" {
  description = "Port for process-video service"
  type        = number
  default     = 8080
}

# ─── ECS ─────────────────────────────────────────────────────────────────────
variable "ms_video_desired_count" {
  description = "Desired task count for ms-video"
  type        = number
  default     = 1
}

variable "process_video_desired_count" {
  description = "Desired task count for process-video"
  type        = number
  default     = 1
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}
