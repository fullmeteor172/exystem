output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.node.id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC Provider for EKS"
  value       = aws_iam_openid_connect_provider.cluster.url
}

output "karpenter_irsa_arn" {
  description = "ARN of the Karpenter IAM role for service account"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_node_iam_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_iam_role_name" {
  description = "Name of the Karpenter node IAM role"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter instance profile"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "karpenter_queue_name" {
  description = "Name of the Karpenter SQS queue"
  value       = aws_sqs_queue.karpenter.name
}

output "ebs_csi_driver_irsa_arn" {
  description = "ARN of the EBS CSI driver IAM role for service account"
  value       = aws_iam_role.ebs_csi_driver.arn
}
