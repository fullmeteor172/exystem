variable "name" {
  description = "Name prefix for bastion resources (typically cluster name)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet for the bastion host"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for bastion"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the bastion"
  type        = list(string)
  default     = []
}

variable "enable_efs" {
  description = "Whether EFS is enabled (controls security group rule creation)"
  type        = bool
  default     = false
}

variable "efs_id" {
  description = "EFS file system ID to mount (optional)"
  type        = string
  default     = ""
}

variable "efs_mount_path" {
  description = "Path to mount EFS on the bastion"
  type        = string
  default     = "/mnt/efs"
}

variable "efs_security_group_id" {
  description = "Security group ID of the EFS (to add ingress rule)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
