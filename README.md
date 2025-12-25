# Exystem

Production-ready EKS clusters with Karpenter autoscaling, Traefik ingress, and automated SSL.

## What You Get

**Core Infrastructure:**
- VPC with public/private subnets across 3 availability zones
- EKS cluster with Karpenter for cost-efficient node autoscaling
- Traefik ingress controller with NLB
- Cert-manager with Let's Encrypt (DNS01 via Cloudflare)
- EBS CSI driver with gp3 storage classes

**Optional Components:**
- PostgreSQL (RDS)
- Redis (ElastiCache)
- Shared storage (EFS)
- Bastion host for debugging
- Observability stack (Prometheus, Grafana, Loki)

## Quick Start

```bash
cd terraform

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform apply

# Connect
eval "$(terraform output -raw configure_kubectl)"
kubectl get nodes
```

## Configuration

Required variables in `terraform.tfvars`:

```hcl
project_name = "myapp"
environment  = "dev"
domain_name  = "example.com"
acme_email   = "admin@example.com"

# For automatic DNS and SSL certificates
cloudflare_api_token = "..."
cloudflare_zone_id   = "..."
```

Enable optional components:

```hcl
enable_observability = true   # Prometheus/Grafana/Loki
enable_rds           = true   # PostgreSQL
enable_elasticache   = true   # Redis
enable_efs           = true   # Shared storage
enable_bastion       = true   # Debug host
```

DNS automation is enabled by default. To manage DNS records manually:

```hcl
enable_automatic_dns = false
```

## Initial Node Configuration

Karpenter runs on a managed node group. Defaults: 3x t3.medium (6 vCPU, 12GB RAM).

```hcl
karpenter_initial_instance_type = "t3.medium"
karpenter_initial_desired_size  = 3
karpenter_initial_min_size      = 2
karpenter_initial_max_size      = 5
```

## Multiple Clusters

Each cluster has its own state file. Use `switch.sh` to manage:

```bash
./switch.sh myapp staging
# Update terraform.tfvars to match
terraform apply
```

## Architecture

```
Internet
    |
Cloudflare (DNS + optional proxy)
    |
AWS NLB (internet-facing)
    |
Traefik Ingress (pods in private subnets)
    |
Application pods (Karpenter-managed nodes)
```

**Node Provisioning:**
1. Initial managed node group runs Karpenter controller
2. Karpenter provisions additional nodes based on pod requirements
3. Consolidation removes underutilized nodes after 30 minutes
4. Spot instances preferred, falls back to on-demand

**Certificate Flow:**
1. Cert-manager requests wildcard certificate from Let's Encrypt
2. DNS01 challenge completed via Cloudflare API
3. Traefik serves certificate for all subdomains

## Observability

When `enable_observability = true`:

- **Grafana**: `https://grafana.{domain_name}` (admin password in Terraform output)
- **Prometheus**: Collects cluster metrics, 15-day retention
- **Loki**: Aggregates logs from all pods, 30-day retention
- **Promtail**: DaemonSet shipping logs to Loki

Pre-configured dashboards for Kubernetes cluster and node metrics.

## Cleanup

```bash
./cleanup.sh      # Interactive
./cleanup.sh -y   # Non-interactive
```

## Troubleshooting

**Karpenter not scaling:**
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
kubectl describe nodepool default
```

**Certificate issues:**
```bash
kubectl describe certificate -n traefik wildcard-cert
kubectl describe clusterissuer letsencrypt-prod
```

**Bastion access:**
```bash
eval "$(terraform output -raw bastion_ssm_command)"
```

See [terraform/README.md](./terraform/README.md) for detailed configuration reference.
