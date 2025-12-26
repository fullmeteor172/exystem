# Exystem - Cloud-Native Infrastructure Platform

A production-ready infrastructure platform with clean separation between cloud provider infrastructure and Kubernetes workloads.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXYSTEM PLATFORM                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                     LAYER 3: GITOPS (ArgoCD)                            │ │
│  │  Continuous deployment, application management, GitOps workflows        │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                    ▲                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                 LAYER 2: WORKLOADS (Helmfile)                           │ │
│  │  Traefik │ Cert-Manager │ External-DNS │ Prometheus │ Grafana │ Loki   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                    ▲                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                 LAYER 1: INFRASTRUCTURE (Terraform)                      │ │
│  │  VPC │ EKS │ Karpenter │ EBS CSI │ RDS │ ElastiCache │ EFS │ Bastion   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                    ▲                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        AWS CLOUD PROVIDER                                │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
exystem/
├── terraform-aws/              # AWS-specific infrastructure
│   ├── modules/
│   │   ├── networking/         # VPC, subnets, NAT
│   │   ├── eks/               # EKS cluster, IAM, OIDC
│   │   ├── karpenter/         # Node autoscaling
│   │   ├── bootstrap/         # CSI drivers, storage classes
│   │   ├── rds/               # PostgreSQL database
│   │   ├── elasticache/       # Redis cache
│   │   ├── efs/               # Shared file storage
│   │   └── bastion/           # Debug access host
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── charts/                     # Provider-agnostic workloads
│   ├── helmfile.yaml          # Main orchestrator
│   ├── helmfile.d/            # Layered deployments
│   │   ├── 00-core.yaml       # Essential components
│   │   ├── 10-networking.yaml # Traefik ingress
│   │   ├── 20-security.yaml   # Cert-manager, External-DNS
│   │   ├── 30-observability.yaml # Prometheus, Grafana, Loki
│   │   ├── 40-gitops.yaml     # ArgoCD
│   │   └── 50-applications.yaml # User applications
│   ├── values/                # Environment configurations
│   │   ├── common.yaml
│   │   ├── dev.yaml
│   │   ├── staging.yaml
│   │   └── prod.yaml
│   ├── secrets/               # Encrypted secrets (gitignored)
│   └── manifests/             # Raw Kubernetes manifests
│
└── scripts/                   # Automation scripts
    └── deploy.sh              # Unified deployment
```

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.6.0
- kubectl
- Helm >= 3.x
- Helmfile >= 0.150.0

### 1. Deploy Infrastructure

```bash
cd terraform-aws

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# Initialize and deploy
terraform init
terraform plan
terraform apply

# Configure kubectl
eval $(terraform output -raw configure_kubectl)
```

### 2. Deploy Workloads

```bash
cd charts

# Copy and configure secrets
cp secrets/dev.yaml.example secrets/dev.yaml
# Edit secrets/dev.yaml with your credentials

# Deploy all workloads
helmfile sync

# Or deploy to a specific environment
helmfile -e staging sync
```

### 3. Unified Deployment

For a one-command deployment:

```bash
./scripts/deploy.sh --env dev
```

## Design Principles

### Clean Separation

- **Terraform (Layer 1)**: Cloud provider infrastructure that changes infrequently
- **Helmfile (Layer 2)**: Kubernetes workloads that change regularly
- **ArgoCD (Layer 3)**: Continuous deployment and GitOps

### Multi-Cloud Ready

The `charts/` directory is provider-agnostic. To add another cloud provider:

1. Create `terraform-gcp/` or `terraform-azure/`
2. Implement the same module interface
3. Reuse `charts/` unchanged

### GitOps Friendly

- ArgoCD can watch `charts/` for automated deployments
- All configuration is declarative and version-controlled
- Secrets are encrypted or externalized

## Components

### Infrastructure (Terraform)

| Component | Description |
|-----------|-------------|
| Networking | VPC, public/private subnets, NAT Gateway |
| EKS | Kubernetes cluster with OIDC |
| Karpenter | Intelligent node autoscaling |
| Bootstrap | EBS CSI driver, storage classes, metrics-server |
| RDS | PostgreSQL database (optional) |
| ElastiCache | Redis cache (optional) |
| EFS | Shared file system (optional) |
| Bastion | Debug/access host (optional) |

### Workloads (Helmfile)

| Component | Description |
|-----------|-------------|
| Traefik | Ingress controller with AWS NLB |
| Cert-Manager | TLS certificate automation |
| External-DNS | Automatic DNS record management |
| Prometheus | Metrics collection and alerting |
| Grafana | Dashboards and visualization |
| Loki | Log aggregation |
| Promtail | Log collection |
| ArgoCD | GitOps continuous deployment |

## Environment Configuration

### Terraform Variables

Configure in `terraform-aws/terraform.tfvars`:

```hcl
project_name = "exystem"
environment  = "dev"
aws_region   = "us-west-2"

# Feature flags
enable_rds         = false
enable_elasticache = false
enable_efs         = false
enable_bastion     = false
```

### Helmfile Values

Configure in `charts/values/<env>.yaml`:

```yaml
clusterName: "exystem-dev"
domain: "dev.example.com"

observability:
  enabled: true

argocd:
  enabled: false
```

## Operations

### Switching Clusters

```bash
cd terraform-aws
./switch.sh exystem staging
```

### Cleanup

```bash
cd terraform-aws
./cleanup.sh
```

### Layer-specific Deployment

```bash
# Deploy only networking layer
helmfile -l layer=networking sync

# Deploy only observability
helmfile -l layer=observability sync
```

## Access Points

After deployment:

| Service | URL |
|---------|-----|
| Grafana | `https://grafana.<domain>` |
| ArgoCD | `https://argocd.<domain>` |

## Troubleshooting

### Check cluster health

```bash
kubectl get nodes
kubectl get pods -A
```

### Check Karpenter

```bash
kubectl get nodepools,ec2nodeclasses
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

### Check certificates

```bash
kubectl get certificates -A
kubectl get clusterissuers
```

## License

MIT
