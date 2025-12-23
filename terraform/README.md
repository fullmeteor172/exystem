# EKS Infrastructure with Terraform

Modular Terraform configuration for AWS EKS with Karpenter, Traefik, cert-manager, and observability.

## Architecture

### Core Components
- **VPC**: Multi-AZ with public/private subnets
- **EKS**: Managed Kubernetes with IRSA
- **Karpenter**: Node autoscaling
- **Traefik**: Ingress controller with automatic HTTPS
- **Cert-Manager**: Let's Encrypt + Cloudflare DNS

### Optional Components
- **Observability**: Prometheus + Grafana + Loki (logs)
- **RDS**: PostgreSQL database
- **ElastiCache**: Redis cache
- **EFS**: Shared file storage

## Prerequisites

**Tools:**
```bash
brew install terraform awscli kubectl helm
```

**AWS Setup:**
- S3 bucket for Terraform state (e.g., `tf-state-<name>`)
- DynamoDB table for state locking (e.g., `terraform-locks`)
- IAM role with AdministratorAccess (optional, for role assumption)

## Quick Start

### 1. Configure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
```

**Required settings:**
```hcl
project_name = "myproject"
environment  = "dev"
aws_region   = "us-west-2"
domain_name  = "example.com"
acme_email   = "admin@example.com"

# Cloudflare (see API Token section below)
cloudflare_api_token = "your-token"
cloudflare_zone_id   = "your-zone-id"
cloudflare_email     = "your-email"
```

### 2. Cloudflare API Token

Create a token at https://dash.cloudflare.com/profile/api-tokens:

1. Click "Create Token"
2. Use "Edit zone DNS" template
3. Set permissions:
   - **Zone:DNS:Edit**
   - **Zone:Zone:Read**
4. Zone Resources: Include -> Specific zone -> your domain
5. Copy the token to `terraform.tfvars`

### 3. Deploy

```bash
make init    # Initialize Terraform
make plan    # Review changes
make apply   # Deploy infrastructure
```

**Duration**: ~20-30 minutes for initial deployment

### 4. Access the Cluster

```bash
make kubeconfig  # Configure kubectl
kubectl get nodes
```

## Using the Makefile

```bash
make help            # Show all commands
make init            # Initialize Terraform
make plan            # Plan changes
make apply           # Apply changes
make destroy         # Destroy (use cleanup.sh for full cleanup)
make kubeconfig      # Configure kubectl
make verify          # Check cluster health
make output          # Show outputs
make grafana-password # Get Grafana password
make rds-password    # Get RDS password
```

## Accessing Services

### Grafana (if observability enabled)

```
URL: https://grafana.<your-domain>
User: admin
Password: make grafana-password
```

Pre-configured dashboards for Kubernetes and node metrics.

### Creating Ingress

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

Cert-manager will automatically provision and renew certificates.

## Module Structure

```
terraform/
├── main.tf              # Root module
├── variables.tf         # Input variables
├── outputs.tf           # Outputs
├── terraform.tfvars     # Your config (gitignored)
├── cleanup.sh           # Full cleanup script
├── Makefile             # Helper commands
└── modules/
    ├── networking/      # VPC, subnets
    ├── eks/             # EKS cluster
    ├── karpenter/       # Node autoscaling
    ├── addons/          # Traefik, cert-manager, CSI drivers
    ├── observability/   # Prometheus, Grafana, Loki
    ├── rds/             # PostgreSQL
    ├── elasticache/     # Redis
    └── efs/             # Shared storage
```

## Cost Optimization

### Development
```hcl
single_nat_gateway = true
rds_instance_class = "db.t4g.micro"
elasticache_node_type = "cache.t4g.micro"
karpenter_node_capacity_type = ["spot"]
prometheus_retention_days = 7
loki_retention_days = 7
```

### Production
```hcl
single_nat_gateway = false
rds_multi_az = true
elasticache_automatic_failover = true
elasticache_num_cache_nodes = 2
karpenter_node_capacity_type = ["spot", "on-demand"]
prometheus_retention_days = 30
loki_retention_days = 30
```

## Cleanup

For complete cleanup including orphaned AWS resources:

```bash
./cleanup.sh
```

This script:
1. Removes Helm releases and Kubernetes resources
2. Empties S3 buckets
3. Disables RDS deletion protection
4. Runs terraform destroy
5. Cleans up orphaned load balancers, volumes, security groups
6. Optionally resets Terraform state

## Troubleshooting

### Nodes not scaling

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
kubectl get nodepools,ec2nodeclasses
```

### Certificates not issuing

```bash
kubectl logs -n cert-manager -l app=cert-manager
kubectl describe certificate -A
```

### Can't connect to RDS/ElastiCache

```bash
# From within a pod:
kubectl run debug --rm -it --image=busybox -- nslookup <endpoint>
```

## Resources

- [Karpenter](https://karpenter.sh/)
- [Traefik](https://doc.traefik.io/traefik/)
- [Cert-Manager](https://cert-manager.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
