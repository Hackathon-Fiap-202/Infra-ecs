# ─── Application Auto Scaling ────────────────────────────────────────────────
# Limits: min 1 task, max 2 tasks per service (ms-video) / max 4 tasks (process-video)
# Trigger: CPU average > 70%
# Scale-out cooldown: 60s  | Scale-in cooldown: 300s (avoids flapping on Spot)

# ── ms-video ──────────────────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "ms_video" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.ms_video.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 2
}

resource "aws_appautoscaling_policy" "ms_video_cpu" {
  name               = "${var.project_name}-ms-video-cpu-tracking"
  service_namespace  = aws_appautoscaling_target.ms_video.service_namespace
  resource_id        = aws_appautoscaling_target.ms_video.resource_id
  scalable_dimension = aws_appautoscaling_target.ms_video.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value     = 70.0
    disable_scale_in = false

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}

# ── process-video ─────────────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "process_video" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.process_video.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "process_video_cpu" {
  name               = "${var.project_name}-process-video-cpu-tracking"
  service_namespace  = aws_appautoscaling_target.process_video.service_namespace
  resource_id        = aws_appautoscaling_target.process_video.resource_id
  scalable_dimension = aws_appautoscaling_target.process_video.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value     = 70.0
    disable_scale_in = false

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
