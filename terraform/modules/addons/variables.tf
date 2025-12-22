variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "ebs_csi_driver_irsa_arn" {
  description = "ARN of the EBS CSI driver IRSA role"
  type        = string
}

variable "traefik_namespace" {
  description = "Namespace for Traefik"
  type        = string
  default     = "traefik"
}

variable "cert_manager_namespace" {
  description = "Namespace for Cert Manager"
  type        = string
  default     = "cert-manager"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS challenges"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS01 challenges"
  type        = string
  default     = ""
}

variable "cloudflare_email" {
  description = "Cloudflare email"
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email for ACME registration"
  type        = string
}

variable "acme_server" {
  description = "ACME server URL"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "enable_efs" {
  description = "Enable EFS CSI driver"
  type        = bool
  default     = false
}

variable "efs_file_system_id" {
  description = "EFS file system ID"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
