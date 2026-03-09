# ─── Security Group: ALB (public-facing) ─────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the internal ALB fronting ECS tasks"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP from API Gateway VPC Link / internal"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.project_name}-alb-sg" }, var.tags)
}

# ─── Security Group: ECS tasks (app-level ports) ─────────────────────────────
resource "aws_security_group" "ecs_tasks_app" {
  name        = "${var.project_name}-ecs-app-sg"
  description = "Allow ALB to reach ECS tasks on app ports"
  vpc_id      = local.vpc_id

  ingress {
    description     = "ms-video from ALB"
    from_port       = var.ms_video_port
    to_port         = var.ms_video_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "process-video from ALB (internal health check)"
    from_port       = var.process_video_port
    to_port         = var.process_video_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.project_name}-ecs-app-sg" }, var.tags)
}
