# Terraform Configuration

## Usage

```bash
# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply

# Connect to cluster
eval "$(terraform output -raw configure_kubectl)"
```

## Required Variables

| Variable | Description |
|----------|-------------|
| `project_name` | Project identifier used in resource names |
| `environment` | Environment name (dev, staging, prod) |
| `domain_name` | Primary domain for ingress and certificates |
| `acme_email` | Email for Let's Encrypt notifications |

## Cloudflare Integration

For automatic DNS and SSL certificates:

```hcl
cloudflare_api_token = "..."
cloudflare_zone_id   = "..."
```

**API Token Setup:**
1. Go to Cloudflare Dashboard > Profile > API Tokens
2. Create Token using "Edit zone DNS" template
3. Permissions: Zone:DNS:Edit, Zone:Zone:Read
4. Zone Resources: Include your specific domain

**Zone ID:** Found on your domain's Overview page.

To disable automatic DNS record creation:

```hcl
enable_automatic_dns = false
```

This still allows cert-manager to use Cloudflare for certificate challenges, but you must manually create DNS records pointing to the load balancer.

## Optional Components

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_observability` | Prometheus, Grafana, Loki stack | false |
| `enable_rds` | PostgreSQL database | false |
| `enable_elasticache` | Redis cluster | false |
| `enable_efs` | Shared EFS storage | false |
| `enable_bastion` | EC2 for debugging | false |

## Networking

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | 10.0.0.0/16 |
| `availability_zones` | AZs to use (empty = all) | [] |
| `enable_nat_gateway` | Enable NAT for private subnets | true |
| `single_nat_gateway` | Use one NAT (cost saving) | false |

## EKS Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_version` | Kubernetes version | 1.34 |
| `cluster_endpoint_public_access` | Allow public API access | true |
| `cluster_endpoint_private_access` | Allow private API access | true |

## Karpenter Configuration

**Initial Node Group (runs Karpenter controller):**

| Variable | Description | Default |
|----------|-------------|---------|
| `karpenter_initial_instance_type` | Instance type | t3.medium |
| `karpenter_initial_desired_size` | Node count | 3 |
| `karpenter_initial_min_size` | Minimum nodes | 2 |
| `karpenter_initial_max_size` | Maximum nodes | 5 |

**NodePool Configuration:**

| Variable | Description | Default |
|----------|-------------|---------|
| `karpenter_node_instance_types` | Allowed instance types | [t3.medium, t3.large, t3.xlarge, t3.2xlarge] |
| `karpenter_node_capacity_type` | Capacity preference | [spot, on-demand] |

## Observability Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `grafana_admin_password` | Admin password (auto-generated if empty) | "" |
| `prometheus_retention_days` | Metrics retention | 15 |
| `prometheus_storage_size` | Prometheus PVC size | 50Gi |
| `loki_retention_days` | Log retention | 30 |

## RDS Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `rds_engine_version` | PostgreSQL version | 17.2 |
| `rds_instance_class` | Instance size | db.t4g.micro |
| `rds_allocated_storage` | Storage in GB | 20 |
| `rds_multi_az` | Enable Multi-AZ | false |
| `rds_deletion_protection` | Prevent accidental deletion | true |

## ElastiCache Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `elasticache_node_type` | Node size | cache.t4g.micro |
| `elasticache_num_cache_nodes` | Number of nodes | 1 |
| `elasticache_engine_version` | Redis version | 7.1 |
| `elasticache_automatic_failover` | Enable failover (requires 2+ nodes) | false |

## EFS Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `efs_performance_mode` | generalPurpose or maxIO | generalPurpose |
| `efs_throughput_mode` | bursting or provisioned | bursting |

## Multiple Clusters

Each cluster needs a separate state file:

```bash
# Switch to different cluster
./switch.sh myapp staging

# Update terraform.tfvars to match project_name and environment
terraform apply
```

## Outputs

Key outputs after deployment:

```bash
# Cluster connection
terraform output configure_kubectl

# Grafana password (if observability enabled)
terraform output grafana_admin_password

# Load balancer hostname
terraform output traefik_load_balancer_hostname

# Database connection (if RDS enabled)
terraform output rds_endpoint

# Bastion access (if enabled)
terraform output bastion_ssm_command
```

## Cleanup

```bash
# From project root
./cleanup.sh

# Non-interactive
./cleanup.sh -y
```

## Troubleshooting

**Karpenter:**
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
kubectl describe nodepool default
kubectl describe ec2nodeclass default
```

**Certificates:**
```bash
kubectl describe certificate -n traefik wildcard-cert
kubectl describe clusterissuer letsencrypt-prod
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

**External DNS:**
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

**Bastion:**
```bash
# SSH with key
eval "$(terraform output -raw bastion_get_key_command)"
eval "$(terraform output -raw bastion_ssh_command)"

# SSM (no key needed)
eval "$(terraform output -raw bastion_ssm_command)"
```
