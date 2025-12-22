variable "name" {
  description = "Name for the EFS file system"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for mount targets"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access EFS"
  type        = list(string)
}

variable "performance_mode" {
  description = "Performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "Throughput mode (bursting or provisioned)"
  type        = string
  default     = "bursting"
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s"
  type        = number
  default     = null
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
