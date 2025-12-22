variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "node_iam_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the instance profile"
  type        = string
}

variable "irsa_arn" {
  description = "ARN of the Karpenter IRSA role"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue for interruption handling"
  type        = string
}

variable "namespace" {
  description = "Namespace for Karpenter"
  type        = string
  default     = "karpenter"
}

variable "instance_types" {
  description = "List of instance types Karpenter can provision"
  type        = list(string)
}

variable "capacity_types" {
  description = "List of capacity types (spot, on-demand)"
  type        = list(string)
}

variable "subnet_ids" {
  description = "List of subnet IDs for nodes"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for nodes"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
