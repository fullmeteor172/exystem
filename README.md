# Exystem - Production-Grade AWS Infrastructure

This repository contains Terraform infrastructure-as-code for deploying production-grade Kubernetes clusters on AWS EKS.

## 📁 Repository Structure

```
exystem/
├── terraform/          # Main Terraform infrastructure code
│   ├── modules/       # Reusable Terraform modules
│   ├── README.md      # Detailed infrastructure documentation
│   └── ...
└── README.md          # This file
```

## 🚀 Quick Start

Navigate to the `terraform/` directory and follow the comprehensive guide:

```bash
cd terraform
cat README.md  # Read the full documentation
```

## 📖 Documentation

All infrastructure documentation is located in [`terraform/README.md`](./terraform/README.md).

This includes:
- Architecture overview
- Prerequisites and setup
- Deployment instructions
- Configuration options
- Common operations
- Troubleshooting guide

## 🏗️ What's Deployed

This infrastructure creates:

- **EKS Cluster** with Karpenter autoscaling
- **Traefik Ingress** with automatic HTTPS via Let's Encrypt
- **Cert-Manager** for SSL certificate management
- **Metrics Server** for resource monitoring
- **AWS EBS CSI Driver** for persistent storage

**Optional components:**
- **Observability Stack** (Prometheus, Loki, Grafana)
- **RDS PostgreSQL** database
- **ElastiCache Redis** cache
- **EFS** file system

## 🎯 Key Features

- ✅ **Fully Modular**: Enable/disable components via feature flags
- ✅ **Production-Ready**: Best practices for security, HA, and cost optimization
- ✅ **Auto-Scaling**: Karpenter for intelligent node provisioning
- ✅ **Automatic HTTPS**: Let's Encrypt + Cloudflare DNS automation
- ✅ **GitOps-Ready**: Structured for easy CI/CD integration
- ✅ **Well Documented**: Comprehensive guides and examples

## 🛠️ Prerequisites

- Terraform >= 1.6.0
- AWS CLI configured
- kubectl
- Helm 3

See [`terraform/README.md`](./terraform/README.md) for detailed setup instructions.

## 📝 License

Internal infrastructure repository.

---

**For detailed documentation, see [`terraform/README.md`](./terraform/README.md)**
