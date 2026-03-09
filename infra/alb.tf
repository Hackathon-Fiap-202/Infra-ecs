# ─── Internal ALB ─────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = "${var.project_name}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.private_subnet_ids

  tags = merge({ Name = "${var.project_name}-internal-alb" }, var.tags)
}

# ─── Target Group: ms-video ──────────────────────────────────────────────────
resource "aws_lb_target_group" "ms_video" {
  name        = "${var.project_name}-ms-video-tg"
  port        = var.ms_video_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge({ Name = "${var.project_name}-ms-video-tg" }, var.tags)
}

# ─── Listener: HTTP :80 ───────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ms_video.arn
  }

  tags = var.tags
}
