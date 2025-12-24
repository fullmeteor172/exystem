################################################################################
# VPC Outputs
################################################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

################################################################################
# EKS Cluster Outputs
################################################################################

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

################################################################################
# kubectl Configuration
################################################################################

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = var.assume_role_arn != "" ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} --role-arn ${var.assume_role_arn} --alias ${module.eks.cluster_name}" : "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

################################################################################
# RDS Outputs
################################################################################

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = var.enable_rds ? module.rds[0].endpoint : null
}

output "rds_database_name" {
  description = "Name of the default database"
  value       = var.enable_rds ? module.rds[0].database_name : null
}

output "rds_master_username" {
  description = "Master username for RDS"
  value       = var.enable_rds ? module.rds[0].master_username : null
  sensitive   = true
}

output "rds_password_secret_arn" {
  description = "ARN of the secret containing RDS password"
  value       = var.enable_rds ? module.rds[0].password_secret_arn : null
}

################################################################################
# ElastiCache Outputs
################################################################################

output "elasticache_endpoint" {
  description = "ElastiCache cluster endpoint"
  value       = var.enable_elasticache ? module.elasticache[0].endpoint : null
}

output "elasticache_port" {
  description = "ElastiCache port"
  value       = var.enable_elasticache ? module.elasticache[0].port : null
}

################################################################################
# EFS Outputs
################################################################################

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = var.enable_efs ? module.efs[0].file_system_id : null
}

output "efs_file_system_dns_name" {
  description = "DNS name of the EFS file system"
  value       = var.enable_efs ? module.efs[0].file_system_dns_name : null
}

################################################################################
# Observability Outputs
################################################################################

output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = var.enable_observability ? "https://grafana.${var.domain_name}" : null
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = var.enable_observability ? module.observability[0].grafana_admin_password : null
  sensitive   = true
}

################################################################################
# Bastion Outputs
################################################################################

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = var.enable_bastion ? module.bastion[0].public_ip : null
}

output "bastion_ssh_command" {
  description = "Command to SSH to the bastion"
  value       = var.enable_bastion ? module.bastion[0].ssh_command : null
}

output "bastion_get_key_command" {
  description = "Command to retrieve SSH key from Secrets Manager"
  value       = var.enable_bastion ? module.bastion[0].get_key_command : null
}

output "bastion_ssm_command" {
  description = "Command to connect via SSM (no SSH key needed)"
  value       = var.enable_bastion ? module.bastion[0].ssm_command : null
}

################################################################################
# Quick Reference
################################################################################

output "quick_start" {
  description = "Quick start commands after deployment"
  value = {
    configure_kubectl = var.assume_role_arn != "" ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.name} --role-arn ${var.assume_role_arn}" : "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.name}"
    verify_cluster    = "kubectl get nodes"
    check_karpenter   = "kubectl get nodepools,ec2nodeclasses"
  }
}
