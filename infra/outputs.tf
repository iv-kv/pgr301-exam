output "service_url" {
  description = "Public URL of the service"
  value       = try(aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint, null)
}

output "dashboard_name" {
  description = "CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "s3_bucket" {
  description = "Bucket for uploaded images"
  value       = aws_s3_bucket.images.bucket
}
