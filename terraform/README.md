# EKS Provisioning Tool

Production-grade AWS EKS infrastructure with modular, optional components. Supports multiple isolated clusters.

## Quick Start

```bash
# 1. Setup a new cluster (creates isolated state)
./setup.sh myproject dev

# 2. Review what will be created
./plan.sh

# 3. Deploy
terraform apply

# 4. Configure kubectl
make kubeconfig

# 5. Verify
make verify
```

## Features

| Component | Description | Default |
|-----------|-------------|---------|
| **EKS Cluster** | Kubernetes control plane | Always |
| **Karpenter** | Node autoscaling | Always |
| **Traefik** | Ingress controller with NLB | Always |
| **Cert-Manager** | Automatic TLS certificates | Always |
| **EBS CSI** | Persistent volume support | Always |
| **Metrics Server** | Resource metrics for HPA | Always |
| **RDS PostgreSQL** | Managed database | Optional |
| **ElastiCache Redis** | Managed cache | Optional |
| **EFS** | Shared file storage | Optional |
| **Bastion Host** | SSH/EFS access point | Optional |
| **Observability** | Prometheus/Grafana/Loki | Optional |

## Multi-Cluster Support

Each cluster is completely isolated with its own:
- Terraform state file in S3
- AWS resources (no naming conflicts)
- Kubernetes cluster

### Running Multiple Clusters

```bash
# Cluster 1: Development
./setup.sh myapp dev
terraform apply

# Cluster 2: Staging (separate terminal or after switching)
./setup.sh myapp staging
terraform apply

# List all clusters
make list-clusters
```

### Switching Between Clusters

```bash
# Switch to a different cluster
./setup.sh myapp staging

# Now all commands apply to staging
terraform plan
make kubeconfig
kubectl get nodes
```

## Configuration

### terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Key settings:

```hcl
# Required
project_name = "myapp"
environment  = "dev"
domain_name  = "example.com"
acme_email   = "admin@example.com"

# Cloudflare (for automatic DNS/SSL)
cloudflare_api_token = "your-token"
cloudflare_zone_id   = "your-zone-id"

# Optional components
enable_rds           = false  # PostgreSQL database
enable_elasticache   = false  # Redis cache
enable_efs           = false  # Shared storage
enable_bastion       = false  # Bastion host for EFS access
enable_observability = false  # Prometheus/Grafana/Loki
```

### Cloudflare API Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Create Token → "Edit zone DNS" template
3. Set permissions: Zone:DNS:Edit, Zone:Zone:Read
4. Zone Resources: Include → Specific zone → your domain
5. Copy token to `terraform.tfvars`

## Commands

### Make Targets

```bash
make help            # Show all commands
make setup           # Initialize new cluster
make plan            # Run terraform plan
make apply           # Deploy infrastructure
make verify          # Check cluster health
make kubeconfig      # Configure kubectl
make summary         # Show resource summary
make list-clusters   # List all deployed clusters
make destroy         # Destroy with confirmation
make grafana-password # Get Grafana password
make rds-password    # Get RDS password
```

### Scripts

| Script | Purpose |
|--------|---------|
| `./setup.sh` | Initialize cluster with isolated state |
| `./plan.sh` | Show what will be created with cost estimates |
| `./cleanup.sh` | Complete teardown including orphaned resources |

## Bastion Host

The bastion provides SSH access to the VPC and mounts EFS automatically.

### Enable Bastion

```hcl
enable_efs     = true  # Bastion mounts EFS at /mnt/efs
enable_bastion = true
```

### Connect via SSH

```bash
# Get the SSH key from Secrets Manager
eval "$(terraform output -raw bastion_get_key_command)"

# SSH to bastion
eval "$(terraform output -raw bastion_ssh_command)"
```

### Connect via SSM (no key needed)

```bash
eval "$(terraform output -raw bastion_ssm_command)"
```

### What's Installed

- kubectl, helm, aws-cli, git
- EFS mounted at `/mnt/efs`
- Helpful aliases (k, kgp, kgn, efs)

## Karpenter

Karpenter automatically scales nodes based on pending pods.

### Default Configuration

- Instance types: t3.medium, t3.large, t3.xlarge, t3.2xlarge
- Capacity types: spot, on-demand
- Consolidation: After 30 minutes of underutilization

### Customize Instances

```hcl
karpenter_node_instance_types = [
  "m5.large",
  "m5.xlarge",
  "c5.large"
]

karpenter_node_capacity_type = ["spot", "on-demand"]
```

### Verify Karpenter

```bash
# Check NodePool and EC2NodeClass
kubectl get nodepools,ec2nodeclasses

# Watch nodes scaling
kubectl get nodes -w

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

## Cleanup

### Full Teardown

```bash
# Interactive
./cleanup.sh

# Non-interactive (for CI/CD)
./cleanup.sh -y

# Also reset state
./cleanup.sh -y --reset-state
```

### What Gets Cleaned

1. Kubernetes resources (Helm releases, ingresses, PVCs)
2. S3 buckets (excluding Terraform state)
3. Terraform destroy
4. Orphaned AWS resources (load balancers, volumes, security groups)
5. Optional: Terraform state reset

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│                    NLB (Traefik)                             │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│                         VPC                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Public Subnets (3 AZs)                     ││
│  │  [NAT Gateway] [Bastion*]                               ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Private Subnets (3 AZs)                    ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │                 EKS Cluster                         │││
│  │  │  [Karpenter] [Traefik] [Cert-Manager]              │││
│  │  │  [Your Workloads...]                                │││
│  │  └─────────────────────────────────────────────────────┘││
│  │  [RDS*] [ElastiCache*] [EFS Mount Targets*]            ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
* = Optional components
```

## Cost Estimates

| Component | Monthly Cost |
|-----------|-------------|
| EKS Control Plane | ~$72 |
| NAT Gateway (single) | ~$32 + data |
| 2x t3.large (initial) | ~$120 |
| RDS db.t4g.micro | ~$13 |
| ElastiCache t4g.micro | ~$12 |
| Bastion t3.micro | ~$8 |
| EFS | $0.30/GB |

Karpenter nodes are billed based on actual usage (spot pricing when available).

### Cost Optimization for Dev

```hcl
single_nat_gateway = true
karpenter_node_capacity_type = ["spot"]
enable_observability = false
```

### Production Settings

```hcl
single_nat_gateway = false       # HA NAT per AZ
rds_multi_az = true              # RDS failover
elasticache_num_cache_nodes = 2  # Redis replicas
```

## Ingress Example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
  tls:
  - hosts:
    - app.example.com
    secretName: my-app-tls
```

## Troubleshooting

### Pods Stuck Pending

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check NodePool status
kubectl describe nodepool default

# Check EC2NodeClass
kubectl describe ec2nodeclass default
```

### Terraform State Issues

```bash
# Force unlock
terraform force-unlock <LOCK_ID>

# Reinitialize
rm -rf .terraform
./setup.sh myapp dev
```

### Certificates Not Issuing

```bash
kubectl logs -n cert-manager -l app=cert-manager
kubectl describe certificate -A
kubectl describe certificaterequest -A
```

## Module Structure

```
terraform/
├── main.tf              # Root module
├── variables.tf         # Input variables
├── outputs.tf           # Outputs
├── backend.tf           # S3 state backend
├── setup.sh             # Cluster initialization
├── plan.sh              # Enhanced plan view
├── cleanup.sh           # Complete teardown
├── Makefile             # Helper commands
├── terraform.tfvars     # Your config (gitignored)
└── modules/
    ├── networking/      # VPC, subnets, NAT
    ├── eks/             # EKS cluster, IAM, OIDC
    ├── karpenter/       # Node autoscaling
    ├── addons/          # Traefik, cert-manager, CSI
    ├── observability/   # Prometheus, Grafana, Loki
    ├── rds/             # PostgreSQL
    ├── elasticache/     # Redis
    ├── efs/             # Shared storage
    └── bastion/         # SSH access host
```

## Resources

- [Karpenter Docs](https://karpenter.sh/)
- [Traefik Docs](https://doc.traefik.io/traefik/)
- [Cert-Manager Docs](https://cert-manager.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
