output "traefik_namespace" {
  description = "Namespace where Traefik is deployed"
  value       = var.traefik_namespace
}

output "cert_manager_namespace" {
  description = "Namespace where Cert Manager is deployed"
  value       = var.cert_manager_namespace
}

output "traefik_load_balancer_hostname" {
  description = "Hostname of the Traefik load balancer"
  value       = try(helm_release.traefik.status[0].load_balancer[0].ingress[0].hostname, "pending")
}
