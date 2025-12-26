################################################################################
# General Configuration
################################################################################

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume for Terraform operations (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Networking Configuration
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use. If empty, will use first 3 AZs in the region"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets (cost savings)"
  type        = bool
  default     = false
}

################################################################################
# EKS Cluster Configuration
################################################################################

variable "cluster_version" {
  description = "Kubernetes version to use for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant cluster creator admin permissions"
  type        = bool
  default     = true
}

################################################################################
# Karpenter Configuration
################################################################################

variable "karpenter_namespace" {
  description = "Namespace for Karpenter"
  type        = string
  default     = "karpenter"
}

variable "karpenter_node_instance_types" {
  description = "List of instance types Karpenter can provision"
  type        = list(string)
  default     = ["t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge"]
}

variable "karpenter_node_capacity_type" {
  description = "Capacity type for Karpenter nodes (on-demand or spot)"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

# Initial node group configuration (where Karpenter itself runs)
variable "karpenter_initial_instance_type" {
  description = "Instance type for initial Karpenter node group"
  type        = string
  default     = "t3.medium"
}

variable "karpenter_initial_desired_size" {
  description = "Desired number of nodes in initial Karpenter node group"
  type        = number
  default     = 3
}

variable "karpenter_initial_min_size" {
  description = "Minimum number of nodes in initial Karpenter node group"
  type        = number
  default     = 2
}

variable "karpenter_initial_max_size" {
  description = "Maximum number of nodes in initial Karpenter node group"
  type        = number
  default     = 5
}

################################################################################
# RDS Configuration
################################################################################

variable "enable_rds" {
  description = "Enable RDS PostgreSQL database"
  type        = bool
  default     = false
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "17.2"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "rds_database_name" {
  description = "Name of the default database"
  type        = string
  default     = "app"
}

variable "rds_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "postgres"
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "rds_multi_az" {
  description = "Enable multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS (disable for dev/sandbox)"
  type        = bool
  default     = true
}

################################################################################
# ElastiCache Configuration
################################################################################

variable "enable_elasticache" {
  description = "Enable ElastiCache Redis cluster"
  type        = bool
  default     = false
}

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

variable "elasticache_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "elasticache_parameter_group_family" {
  description = "Redis parameter group family"
  type        = string
  default     = "redis7"
}

variable "elasticache_automatic_failover" {
  description = "Enable automatic failover (requires at least 2 nodes)"
  type        = bool
  default     = false
}

################################################################################
# EFS Configuration
################################################################################

variable "enable_efs" {
  description = "Enable EFS file system"
  type        = bool
  default     = false
}

variable "efs_performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode (bursting or provisioned)"
  type        = string
  default     = "bursting"
}

variable "efs_provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (only if throughput_mode is provisioned)"
  type        = number
  default     = null
}

################################################################################
# Bastion Configuration
################################################################################

variable "enable_bastion" {
  description = "Enable bastion host for EFS access and debugging"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_efs_mount_path" {
  description = "Path to mount EFS on the bastion host"
  type        = string
  default     = "/mnt/efs"
}
