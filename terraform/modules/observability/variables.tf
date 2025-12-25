variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Namespace for observability stack"
  type        = string
  default     = "observability"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana (auto-generated if empty)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "loki_retention_days" {
  description = "Number of days to retain logs in Loki"
  type        = number
  default     = 30
}

variable "prometheus_retention_days" {
  description = "Number of days to retain metrics in Prometheus"
  type        = number
  default     = 15
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "domain_name" {
  description = "Domain name for ingress"
  type        = string
}

variable "enable_cert_manager" {
  description = "Whether cert-manager is configured (to create certificates)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
