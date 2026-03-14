output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "alb_dns_name" {
  description = "Internal ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "Internal ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_listener_arn" {
  description = "HTTP listener ARN (used by API Gateway VPC Link integration)"
  value       = aws_lb_listener.http.arn
}

output "ms_video_service_name" {
  description = "ECS service name for ms-video"
  value       = aws_ecs_service.ms_video.name
}

output "process_video_service_name" {
  description = "ECS service name for process-video"
  value       = aws_ecs_service.process_video.name
}

output "ms_video_target_group_arn" {
  description = "Target group ARN for ms-video"
  value       = aws_lb_target_group.ms_video.arn
}
