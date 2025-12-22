output "traefik_namespace" {
  description = "Namespace where Traefik is deployed"
  value       = var.traefik_namespace
}

output "cert_manager_namespace" {
  description = "Namespace where Cert Manager is deployed"
  value       = var.cert_manager_namespace
}
