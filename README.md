# Exystem - AWS EKS Provisioning Tool

Provision production-grade Kubernetes clusters on AWS EKS with modular, optional components.

## Quick Start

```bash
cd terraform

# 1. Initialize a new cluster (creates isolated state)
./setup.sh myapp dev

# 2. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# 3. Review what will be created
./plan.sh

# 4. Deploy
terraform apply

# 5. Access the cluster
make kubeconfig
kubectl get nodes
```

## What Gets Created

**Core (Always Created):**
- VPC with public/private subnets across 3 AZs
- EKS cluster with Karpenter autoscaling
- Traefik ingress controller with NLB
- Cert-manager with Let's Encrypt integration
- EBS CSI driver for persistent storage
- Metrics Server for HPA

**Optional Components:**
- PostgreSQL database (RDS)
- Redis cache (ElastiCache)
- Shared storage (EFS)
- Bastion host for SSH/EFS access
- Observability stack (Prometheus/Grafana/Loki)

## Key Features

- **Multi-Cluster**: Run multiple isolated clusters without conflicts
- **Modular**: Enable/disable components via flags
- **Auto-Scaling**: Karpenter for intelligent node provisioning
- **Automatic HTTPS**: Let's Encrypt + Cloudflare DNS
- **Clean Teardown**: Full cleanup of all resources

## Multi-Cluster Support

Each cluster is completely isolated with its own state and resources:

```bash
# Cluster 1: Development
./setup.sh myapp dev && terraform apply

# Cluster 2: Staging
./setup.sh myapp staging && terraform apply

# List all clusters
make list-clusters
```

## Cleanup

```bash
# Full teardown (handles orphaned resources)
./cleanup.sh

# Non-interactive for CI/CD
./cleanup.sh -y --reset-state
```

## Documentation

Full documentation: [`terraform/README.md`](./terraform/README.md)

## Prerequisites

- Terraform >= 1.6.0
- AWS CLI configured
- kubectl
- Helm 3

## Repository Structure

```
exystem/
├── terraform/
│   ├── modules/
│   │   ├── networking/    # VPC, subnets
│   │   ├── eks/           # EKS cluster, IAM
│   │   ├── karpenter/     # Node autoscaling
│   │   ├── addons/        # Traefik, cert-manager
│   │   ├── observability/ # Prometheus, Grafana, Loki
│   │   ├── rds/           # PostgreSQL
│   │   ├── elasticache/   # Redis
│   │   ├── efs/           # Shared storage
│   │   └── bastion/       # SSH access host
│   ├── setup.sh           # Cluster initialization
│   ├── plan.sh            # Enhanced plan view
│   ├── cleanup.sh         # Complete teardown
│   └── Makefile           # Helper commands
└── README.md
```
