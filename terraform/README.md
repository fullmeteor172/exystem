# EKS Infrastructure with Terraform

A production-ready, modular Terraform configuration for deploying an AWS EKS cluster with Karpenter autoscaling, Traefik ingress, automatic SSL certificate management, and optional observability stack.

## 🏗️ Architecture Overview

This infrastructure deploys:

### **Core Components (Always Installed)**
- **VPC**: Multi-AZ VPC with public and private subnets
- **EKS Cluster**: Managed Kubernetes cluster with IRSA support
- **Karpenter**: Advanced node autoscaler (replaces Cluster Autoscaler)
- **Traefik**: Modern ingress controller with automatic HTTPS
- **AWS EBS CSI Driver**: For persistent volume support
- **Metrics Server**: For `kubectl top` and HPA support
- **Cert-Manager**: Automatic SSL certificate management via Let's Encrypt + Cloudflare

### **Optional Components (Feature Flags)**
- **Observability Stack**:
  - Prometheus (metrics collection and alerting)
  - Loki (log aggregation with S3 backend)
  - Grafana (visualization with pre-configured dashboards)
  - Promtail (log shipper)
- **RDS PostgreSQL**: Managed relational database
- **ElastiCache Redis**: Managed in-memory cache
- **EFS**: Elastic File System for shared storage
- **EFS CSI Driver**: For EFS persistent volumes (auto-installed if EFS enabled)

## 📋 Prerequisites

### 1. AWS Account Setup

You should have already completed:
- ✅ AWS root account (`meteor`)
- ✅ IAM role `terraform-admin` with AdministratorAccess
- ✅ IAM user `morpheus` with permission to assume `terraform-admin`
- ✅ S3 bucket `tf-state-meteor` for Terraform state
- ✅ DynamoDB table `terraform-locks` for state locking

### 2. Required Tools

Install the following tools on your local machine:

```bash
# Terraform (>= 1.6.0)
brew install terraform

# AWS CLI
brew install awscli

# kubectl
brew install kubectl

# Helm (for managing Kubernetes packages)
brew install helm
```

### 3. AWS Credentials

Configure your AWS credentials for the `morpheus` user with the `terraform-admin` role:

```bash
# ~/.aws/credentials
[morpheus]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY

# ~/.aws/config
[profile morpheus-terraform-admin]
role_arn = arn:aws:iam::143495498599:role/terraform-admin
source_profile = morpheus
region = us-west-2
```

Test the configuration:
```bash
export AWS_PROFILE=morpheus-terraform-admin
aws sts get-caller-identity
```

## 🚀 Quick Start

### 1. Clone and Navigate

```bash
cd terraform
```

### 2. Configure Your Environment

Copy the example configuration:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your settings:
```hcl
# Required configurations
project_name = "exystem"
environment  = "dev"
aws_region   = "us-west-2"

# Cloudflare configuration (for automatic SSL)
cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_email     = "your-email@example.com"
domain_name          = "example.com"
acme_email           = "admin@example.com"

# Optional: Enable observability
enable_observability = true

# Optional: Enable RDS
enable_rds = true

# Optional: Enable Redis
enable_elasticache = true

# Optional: Enable EFS
enable_efs = true
```

### 3. Get Cloudflare API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create a new token with the following permissions:
   - **Zone - DNS - Edit**
   - **Zone - Zone - Read**
3. Select the specific zones (domains) you want to manage
4. Copy the token to `terraform.tfvars`

### 4. Initialize Terraform

```bash
terraform init
```

This will:
- Download required providers (AWS, Kubernetes, Helm)
- Configure the S3 backend for state storage

### 5. Review the Plan

```bash
terraform plan
```

Review the resources that will be created. This is a safe operation that doesn't make any changes.

### 6. Apply the Configuration

```bash
terraform apply
```

Type `yes` to confirm and create the infrastructure.

**⏱️ Expected Duration**: 20-30 minutes for initial deployment

### 7. Configure kubectl

After the deployment completes, configure kubectl to access your cluster:

```bash
# Terraform will output this command, or use:
aws eks update-kubeconfig \
  --region us-west-2 \
  --name exystem-dev \
  --role-arn arn:aws:iam::143495498599:role/terraform-admin \
  --alias exystem-dev

# Verify access
kubectl get nodes
kubectl get pods -A
```

## 📊 Accessing Services

### Grafana (if observability enabled)

```bash
# URL: https://grafana.example.com
# Username: admin
# Password: (from terraform output or auto-generated)

terraform output -raw grafana_admin_password
```

Pre-configured dashboards:
- Kubernetes Cluster Overview
- Kubernetes Pods Monitoring
- Node Exporter Metrics
- Loki Logs

### Prometheus (if observability enabled)

```bash
# URL: https://prometheus.example.com
```

### Traefik Dashboard

The Traefik dashboard is disabled by default for security. To enable it temporarily:

```bash
kubectl port-forward -n traefik $(kubectl get pods -n traefik -l app.kubernetes.io/name=traefik -o name) 9000:9000
# Access at: http://localhost:9000/dashboard/
```

## 🔧 Common Operations

### Scaling Nodes

Karpenter automatically scales nodes based on pod requirements. No manual intervention needed!

To see Karpenter in action:
```bash
# Watch nodes
kubectl get nodes -w

# Deploy a test workload
kubectl create deployment nginx --image=nginx --replicas=10

# Karpenter will automatically provision nodes
```

### Viewing Logs

```bash
# View logs from all pods in a namespace
kubectl logs -n <namespace> <pod-name>

# Or use Grafana with Loki for advanced log querying
# Navigate to: https://grafana.example.com
```

### Updating Cluster Version

1. Update `cluster_version` in `terraform.tfvars`
2. Run `terraform apply`
3. Update node AMIs (Karpenter will automatically use the new version for new nodes)

### Adding a New Ingress

Create an Ingress resource:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
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

Cert-manager will automatically:
- Request a certificate from Let's Encrypt
- Configure DNS via Cloudflare
- Install the certificate
- Auto-renew before expiration

### Accessing RDS Database

```bash
# Get the connection details
terraform output rds_endpoint
terraform output rds_database_name

# Get the password from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_password_secret_arn) \
  --query SecretString \
  --output text | jq -r .password

# Connect from within the cluster
kubectl run -it --rm psql --image=postgres:16 --restart=Never -- \
  psql -h <rds_endpoint> -U postgres -d app
```

### Accessing ElastiCache Redis

```bash
# Get the connection details
terraform output elasticache_endpoint

# Connect from within the cluster
kubectl run -it --rm redis --image=redis:7 --restart=Never -- \
  redis-cli -h <elasticache_endpoint> -p 6379
```

### Using EFS for Persistent Storage

Create a PersistentVolumeClaim:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs
  resources:
    requests:
      storage: 5Gi
```

## 🏗️ Module Structure

```
terraform/
├── main.tf                 # Root module orchestration
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── backend.tf              # S3 backend configuration
├── versions.tf             # Provider versions
├── terraform.tfvars        # Your configuration (not in git)
├── terraform.tfvars.example # Example configuration
│
├── modules/
│   ├── networking/         # VPC, subnets, NAT gateway
│   ├── eks/                # EKS cluster, IRSA, security groups
│   ├── karpenter/          # Karpenter autoscaler
│   ├── addons/             # Core Kubernetes addons
│   ├── observability/      # Prometheus, Loki, Grafana
│   ├── rds/                # PostgreSQL database
│   ├── elasticache/        # Redis cache
│   └── efs/                # Elastic File System
```

## 💰 Cost Optimization

### Development Environment

For development/testing, use these settings to minimize costs:

```hcl
# Use a single NAT gateway
single_nat_gateway = true

# Use smaller instances
rds_instance_class         = "db.t4g.micro"
elasticache_node_type      = "cache.t4g.micro"

# Disable multi-AZ
rds_multi_az = false
elasticache_automatic_failover = false

# Reduce retention periods
prometheus_retention_days = 7
loki_retention_days       = 7
rds_backup_retention_period = 1

# Use Spot instances for Karpenter
karpenter_node_capacity_type = ["spot"]
```

### Production Environment

For production, prioritize reliability:

```hcl
# Use NAT gateway per AZ for HA
single_nat_gateway = false

# Use appropriate instance sizes
rds_instance_class         = "db.r6g.large"
elasticache_node_type      = "cache.r6g.large"

# Enable multi-AZ
rds_multi_az = true
elasticache_automatic_failover = true
elasticache_num_cache_nodes = 2

# Longer retention
prometheus_retention_days = 30
loki_retention_days       = 90
rds_backup_retention_period = 30

# Mix of Spot and On-Demand
karpenter_node_capacity_type = ["spot", "on-demand"]
```

## 🔒 Security Best Practices

1. **Secrets Management**:
   - RDS passwords are auto-generated and stored in AWS Secrets Manager
   - Use Kubernetes secrets for application credentials
   - Never commit `terraform.tfvars` to version control

2. **Network Security**:
   - Private subnets for EKS nodes, RDS, and ElastiCache
   - Security groups with least-privilege access
   - VPC Flow Logs enabled for audit

3. **Cluster Access**:
   - Use IAM roles for service accounts (IRSA)
   - Enable cluster endpoint private access
   - Restrict public access in production

4. **Certificate Management**:
   - Automatic certificate rotation via cert-manager
   - All ingress traffic uses HTTPS
   - Let's Encrypt production certificates

## 🔄 Upgrading

### Terraform Providers

Update provider versions in `versions.tf` and run:
```bash
terraform init -upgrade
terraform plan
terraform apply
```

### Helm Charts

Helm charts are pinned to specific versions in the module code. To upgrade:
1. Update the chart version in the relevant module
2. Review the chart's changelog for breaking changes
3. Run `terraform plan` and `terraform apply`

### Kubernetes Version

1. Update `cluster_version` in `terraform.tfvars`
2. Apply: `terraform apply`
3. Karpenter will automatically use the new version for new nodes
4. Drain and delete old nodes to complete the upgrade

## 🧹 Cleanup

To destroy all resources:

```bash
# DANGER: This will delete everything!
terraform destroy

# You'll need to confirm by typing 'yes'
```

**Note**: Some resources have deletion protection enabled (e.g., RDS). You may need to:
1. Disable deletion protection in the console
2. Run `terraform destroy` again

## 📚 Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter Documentation](https://karpenter.sh/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/)

## 🐛 Troubleshooting

### Pods are pending and nodes aren't scaling

Check Karpenter logs:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

Common issues:
- Instance type not available in AZ
- Service quotas exceeded
- Insufficient IAM permissions

### Certificate not being issued

Check cert-manager logs:
```bash
kubectl logs -n cert-manager -l app=cert-manager
kubectl describe certificate -n <namespace> <cert-name>
kubectl describe certificaterequest -n <namespace>
```

Common issues:
- Incorrect Cloudflare API token
- Domain not managed by Cloudflare
- DNS propagation delay

### Can't connect to RDS/ElastiCache

Verify security groups:
```bash
# Check that pods can resolve the endpoint
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <endpoint>

# Check that the security group allows traffic from EKS nodes
aws ec2 describe-security-groups --group-ids <sg-id>
```

## 📝 License

This infrastructure code is provided as-is for use in your organization.

## 🤝 Contributing

This is an internal infrastructure repository. For changes:
1. Create a new branch
2. Make your changes
3. Test with `terraform plan`
4. Submit a pull request

---

**Built with ❤️ for production-grade Kubernetes on AWS**
