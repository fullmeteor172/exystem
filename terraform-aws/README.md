# Terraform AWS Infrastructure

This directory contains Terraform configuration for provisioning AWS infrastructure that supports Kubernetes workloads.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Region                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                         VPC                                 │ │
│  │  ┌──────────────────┐  ┌──────────────────────────────────┐│ │
│  │  │  Public Subnets  │  │       Private Subnets            ││ │
│  │  │                  │  │                                  ││ │
│  │  │  ┌────────────┐  │  │  ┌────────────┐  ┌────────────┐ ││ │
│  │  │  │   NAT GW   │  │  │  │    EKS     │  │   RDS      │ ││ │
│  │  │  │            │  │  │  │   Nodes    │  │ (optional) │ ││ │
│  │  │  └────────────┘  │  │  └────────────┘  └────────────┘ ││ │
│  │  │                  │  │                                  ││ │
│  │  │  ┌────────────┐  │  │  ┌────────────┐  ┌────────────┐ ││ │
│  │  │  │  Bastion   │  │  │  │ ElastiCache│  │    EFS     │ ││ │
│  │  │  │ (optional) │  │  │  │ (optional) │  │ (optional) │ ││ │
│  │  │  └────────────┘  │  │  └────────────┘  └────────────┘ ││ │
│  │  └──────────────────┘  └──────────────────────────────────┘│ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    EKS Control Plane                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Modules

| Module | Description |
|--------|-------------|
| `networking` | VPC, subnets, NAT Gateway, flow logs |
| `eks` | EKS cluster, IAM roles, OIDC provider, security groups |
| `karpenter` | Node autoscaler with managed initial node group |
| `bootstrap` | EBS CSI driver, storage classes, metrics-server |
| `rds` | PostgreSQL with Secrets Manager integration |
| `elasticache` | Redis with encryption and failover |
| `efs` | Shared file system with mount targets |
| `bastion` | EC2 host with SSM and EFS access |

## Usage

### Initial Setup

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
vim terraform.tfvars

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Configure kubectl

```bash
# Get the configuration command
terraform output configure_kubectl

# Or run it directly
eval $(terraform output -raw configure_kubectl)

# Verify
kubectl get nodes
```

### Switch Environments

```bash
./switch.sh myproject staging
```

### Cleanup

```bash
./cleanup.sh
```

## Configuration Reference

### Required Variables

| Variable | Description |
|----------|-------------|
| `project_name` | Project name for resource naming |
| `environment` | Environment (dev, staging, prod) |

### Optional Features

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_rds` | false | PostgreSQL database |
| `enable_elasticache` | false | Redis cache |
| `enable_efs` | false | Shared file system |
| `enable_bastion` | false | Debug access host |

### Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | 10.0.0.0/16 | VPC CIDR block |
| `single_nat_gateway` | false | Use single NAT (cost savings) |

### EKS

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_version` | 1.31 | Kubernetes version |
| `cluster_endpoint_public_access` | true | Public API access |

### Karpenter

| Variable | Default | Description |
|----------|---------|-------------|
| `karpenter_node_instance_types` | t3.medium-2xlarge | Allowed instance types |
| `karpenter_node_capacity_type` | spot,on-demand | Capacity preference |
| `karpenter_initial_desired_size` | 3 | Initial node count |

## Outputs

After deployment, these outputs are available:

```bash
# Cluster access
terraform output configure_kubectl
terraform output cluster_endpoint

# Optional services (if enabled)
terraform output rds_endpoint
terraform output elasticache_endpoint
terraform output efs_file_system_id
terraform output bastion_ssm_command

# Helmfile integration
terraform output helmfile_config
```

## State Management

State is stored in S3 with DynamoDB locking:

- **Bucket**: tf-state-meteor
- **Lock Table**: terraform-locks
- **Key Pattern**: `{project}/{environment}/terraform.tfstate`

## Best Practices

1. **Use workspaces or separate state files** for different environments
2. **Enable deletion protection** in production (`rds_deletion_protection = true`)
3. **Use spot instances** for cost savings in non-production
4. **Keep secrets in AWS Secrets Manager**, not in Terraform state

## Troubleshooting

### Nodes not joining cluster

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check EC2NodeClass
kubectl get ec2nodeclasses
kubectl describe ec2nodeclass default
```

### EBS volumes not provisioning

```bash
# Check CSI driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check storage classes
kubectl get storageclass
```

### RDS connection issues

```bash
# Get connection details
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_password_secret_arn) \
  --query SecretString --output text
```
