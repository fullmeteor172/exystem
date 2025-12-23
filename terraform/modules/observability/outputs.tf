output "namespace" {
  description = "Namespace where observability stack is deployed"
  value       = var.namespace
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = local.grafana_password
  sensitive   = true
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "https://grafana.${var.domain_name}"
}
