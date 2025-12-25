output "namespace" {
  description = "Namespace where Karpenter is deployed"
  value       = var.namespace
}

output "helm_release_name" {
  description = "Name of the Karpenter Helm release"
  value       = helm_release.karpenter.name
}

output "node_pool_name" {
  description = "Name of the default Karpenter NodePool"
  value       = "default"
}
