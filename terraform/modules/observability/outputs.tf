output "namespace" {
  description = "Namespace where observability stack is deployed"
  value       = var.namespace
}

output "grafana_admin_password" {
  description = "Grafana admin password (randomly generated if not provided)"
  value       = var.grafana_admin_password != "" ? var.grafana_admin_password : try(random_password.grafana_admin[0].result, "")
  sensitive   = true
}

output "loki_s3_bucket" {
  description = "S3 bucket for Loki logs"
  value       = aws_s3_bucket.loki.id
}

output "prometheus_url" {
  description = "URL to access Prometheus"
  value       = "https://prometheus.${var.domain_name}"
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "https://grafana.${var.domain_name}"
}
