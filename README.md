# Exystem - EKS Provisioning

Provision EKS clusters with Karpenter, Traefik, and optional addons.

## Quick Start

```bash
cd terraform

# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# 2. Deploy
terraform init
terraform apply

# 3. Use
eval "$(terraform output -raw configure_kubectl)"
kubectl get nodes
```

## Multiple Clusters

```bash
# Switch to different cluster state
./switch.sh myapp staging

# Update terraform.tfvars to match, then:
terraform plan
terraform apply
```

## What You Get

- VPC with public/private subnets
- EKS with Karpenter autoscaling
- Traefik ingress + cert-manager
- Optional: RDS, Redis, EFS, Bastion, Observability

## Cleanup

```bash
./cleanup.sh
```

See [terraform/README.md](./terraform/README.md) for details.
