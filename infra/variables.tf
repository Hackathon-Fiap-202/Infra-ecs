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
# vpc_id, private_subnet_ids, public_subnet_ids are consumed via remote state locals — no vars needed

# ─── ECR ─────────────────────────────────────────────────────────────────────
# ms_video_ecr_url and process_video_ecr_url are consumed via remote state locals — no vars needed

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# ─── Secrets Manager (from infra-core remote state) ─────────────────────────
# docdb_secret_arn is consumed via remote state locals — no var needed

# ─── SQS ─────────────────────────────────────────────────────────────────────
# SQS URLs are constructed dynamically in locals from var.aws_account_id + var.aws_region

# ─── S3 ──────────────────────────────────────────────────────────────────────
variable "s3_bucket_name" {
  description = "Single S3 bucket for all video storage"
  type        = string
  default     = "nextime-frame-video-storage"
}

variable "s3_input_prefix" {
  description = "S3 key prefix for input videos"
  type        = string
  default     = "video-input-storage/"
}

variable "s3_processed_prefix" {
  description = "S3 key prefix for processed video output"
  type        = string
  default     = "video-processed-storage/"
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
  default     = 2
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for ECS tasks (4096 = 4 vCPU)"
  type        = string
  default     = "4096"
}

variable "task_memory" {
  description = "Memory in MB for ECS tasks"
  type        = string
  default     = "8192"
}

# ─── Datadog ──────────────────────────────────────────────────────────────────
variable "dd_site" {
  description = "Datadog intake site — datadoghq.com (US) or datadoghq.eu (EU)"
  type        = string
  default     = "datadoghq.com"
}

variable "datadog_api_key_secret_arn" {
  description = "Fallback ARN for the Datadog API key secret. Normally resolved automatically from infra-core remote state. Set this only if infra-core has not been applied yet and the remote state output does not exist."
  type        = string
  default     = ""
}
