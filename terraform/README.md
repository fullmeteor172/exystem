# EKS Provisioning

## Usage

```bash
# 1. Copy and edit config
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set project_name, environment, domain_name, etc.

# 2. Initialize (first time only)
terraform init

# 3. Deploy
terraform plan
terraform apply

# 4. Configure kubectl
eval "$(terraform output -raw configure_kubectl)"
kubectl get nodes
```

## Multiple Clusters

Each cluster needs its own state file. Use `switch.sh` to switch between clusters:

```bash
# Switch to exystem-sandbox
./switch.sh exystem sandbox

# Now edit terraform.tfvars to match:
#   project_name = "exystem"
#   environment  = "sandbox"

terraform plan
terraform apply
```

When switching clusters, **you must update terraform.tfvars** to match the project_name and environment.

## What Gets Created

**Always:**
- VPC with 3 public + 3 private subnets
- EKS cluster with Karpenter autoscaling
- Traefik ingress (NLB)
- Cert-manager (Let's Encrypt)
- EBS CSI driver

**Optional (set `enable_X = true` in tfvars):**
- `enable_rds` - PostgreSQL database
- `enable_elasticache` - Redis cache
- `enable_efs` - Shared file storage
- `enable_bastion` - EC2 for SSH/EFS access
- `enable_observability` - Prometheus/Grafana/Loki

## Config Reference

```hcl
# Required
project_name = "myapp"
environment  = "dev"
domain_name  = "example.com"
acme_email   = "admin@example.com"

# Cloudflare (for auto DNS/SSL)
cloudflare_api_token = "..."
cloudflare_zone_id   = "..."

# Optional
enable_rds           = false
enable_elasticache   = false
enable_efs           = false
enable_bastion       = false
enable_observability = false
```

## Cleanup

```bash
# Full cleanup (handles orphaned resources)
./cleanup.sh

# Non-interactive
./cleanup.sh -y
```

## Troubleshooting

### Karpenter not scaling nodes

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
kubectl describe nodepool default
kubectl describe ec2nodeclass default
```

### Bastion access

```bash
# Get SSH key
eval "$(terraform output -raw bastion_get_key_command)"

# SSH in
eval "$(terraform output -raw bastion_ssh_command)"

# Or use SSM (no key needed)
eval "$(terraform output -raw bastion_ssm_command)"
```
