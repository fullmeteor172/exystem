################################################################################
# Provider Configuration
################################################################################

provider "aws" {
  region = var.aws_region

  dynamic "assume_role" {
    for_each = var.assume_role_arn != "" ? [1] : []
    content {
      role_arn = var.assume_role_arn
    }
  }

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "Terraform"
      },
      var.tags
    )
  }
}

# Get current AWS account info
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Configure Kubernetes provider after EKS cluster is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_auth_args
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.eks_auth_args
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.eks_auth_args
  }
}

################################################################################
# Local Variables
################################################################################

locals {
  name = "${var.project_name}-${var.environment}"

  azs = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c"
  ]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # EKS auth args for kubectl/helm providers
  eks_auth_args = var.assume_role_arn != "" ? [
    "eks", "get-token",
    "--cluster-name", module.eks.cluster_name,
    "--region", var.aws_region,
    "--role-arn", var.assume_role_arn
  ] : [
    "eks", "get-token",
    "--cluster-name", module.eks.cluster_name,
    "--region", var.aws_region
  ]
}

################################################################################
# VPC & Networking
################################################################################

module "networking" {
  source = "./modules/networking"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  tags = local.common_tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source = "./modules/eks"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids

  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  cluster_endpoint_private_access          = var.cluster_endpoint_private_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  tags = local.common_tags
}

################################################################################
# Karpenter Node Autoscaler
################################################################################

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name             = module.eks.cluster_name
  cluster_endpoint         = module.eks.cluster_endpoint
  cluster_ca_data          = module.eks.cluster_certificate_authority_data
  cluster_version          = var.cluster_version
  oidc_provider_arn        = module.eks.oidc_provider_arn
  node_iam_role_arn        = module.eks.karpenter_node_iam_role_arn
  node_iam_role_name       = module.eks.karpenter_node_iam_role_name
  irsa_arn                 = module.eks.karpenter_irsa_arn
  queue_name               = module.eks.karpenter_queue_name
  namespace                = var.karpenter_namespace
  instance_types           = var.karpenter_node_instance_types
  capacity_types           = var.karpenter_node_capacity_type
  subnet_ids               = module.networking.private_subnet_ids
  security_group_ids       = [module.eks.node_security_group_id]
  aws_region               = var.aws_region

  # Initial node group configuration
  initial_instance_type = var.karpenter_initial_instance_type
  initial_desired_size  = var.karpenter_initial_desired_size
  initial_min_size      = var.karpenter_initial_min_size
  initial_max_size      = var.karpenter_initial_max_size

  tags = local.common_tags

  depends_on = [module.eks]
}

################################################################################
# Bootstrap - Essential cluster functionality (CSI drivers, storage classes)
################################################################################

module "bootstrap" {
  source = "./modules/bootstrap"

  cluster_name            = module.eks.cluster_name
  cluster_version         = var.cluster_version
  oidc_provider_arn       = module.eks.oidc_provider_arn
  ebs_csi_driver_irsa_arn = module.eks.ebs_csi_driver_irsa_arn

  # EFS configuration
  enable_efs         = var.enable_efs
  efs_file_system_id = var.enable_efs ? module.efs[0].file_system_id : null

  tags = local.common_tags

  depends_on = [module.karpenter]
}

################################################################################
# RDS Database (Optional)
################################################################################

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "./modules/rds"

  identifier     = local.name
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage = var.rds_allocated_storage
  database_name     = var.rds_database_name
  master_username   = var.rds_master_username

  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  backup_retention_period = var.rds_backup_retention_period
  multi_az                = var.rds_multi_az
  deletion_protection     = var.rds_deletion_protection

  tags = local.common_tags
}

################################################################################
# ElastiCache Redis (Optional)
################################################################################

module "elasticache" {
  count  = var.enable_elasticache ? 1 : 0
  source = "./modules/elasticache"

  cluster_id             = local.name
  engine_version         = var.elasticache_engine_version
  node_type              = var.elasticache_node_type
  num_cache_nodes        = var.elasticache_num_cache_nodes
  parameter_group_family = var.elasticache_parameter_group_family
  automatic_failover     = var.elasticache_automatic_failover

  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]

  tags = local.common_tags
}

################################################################################
# EFS File System (Optional)
################################################################################

module "efs" {
  count  = var.enable_efs ? 1 : 0
  source = "./modules/efs"

  name                            = local.name
  vpc_id                          = module.networking.vpc_id
  subnet_ids                      = module.networking.private_subnet_ids
  allowed_security_group_ids      = [module.eks.node_security_group_id]

  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_provisioned_throughput_in_mibps

  tags = local.common_tags
}

################################################################################
# Bastion Host (Optional - for EFS access and debugging)
################################################################################

module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "./modules/bastion"

  name                          = local.name
  vpc_id                        = module.networking.vpc_id
  subnet_id                     = module.networking.public_subnet_ids[0]
  instance_type                 = var.bastion_instance_type
  allowed_ssh_cidrs             = var.bastion_allowed_ssh_cidrs
  additional_security_group_ids = []

  # EFS configuration (only if EFS is enabled)
  enable_efs            = var.enable_efs
  efs_id                = var.enable_efs ? module.efs[0].file_system_id : ""
  efs_mount_path        = var.bastion_efs_mount_path
  efs_security_group_id = var.enable_efs ? module.efs[0].security_group_id : null

  tags = local.common_tags

  depends_on = [module.efs]
}
