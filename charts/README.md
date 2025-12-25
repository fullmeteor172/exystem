# Kubernetes Workloads (Helmfile)

This directory contains Helmfile configuration for deploying Kubernetes workloads on top of cloud infrastructure.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Helmfile Layers                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  50-applications: User Applications (via ArgoCD)           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  40-gitops: ArgoCD                                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  30-observability: Prometheus, Grafana, Loki, Promtail     │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  20-security: Cert-Manager, External-DNS                    │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  10-networking: Traefik Ingress                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  00-core: Reloader (ConfigMap/Secret reload)                │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Prerequisites

- kubectl configured for your cluster
- Helm >= 3.x
- Helmfile >= 0.150.0
- SOPS (optional, for encrypted secrets)

### Deploy All Workloads

```bash
# Update repositories
helmfile repos

# Preview changes
helmfile diff

# Deploy
helmfile sync
```

### Deploy to Specific Environment

```bash
# Development
helmfile -e dev sync

# Staging
helmfile -e staging sync

# Production
helmfile -e prod sync
```

### Deploy Specific Layers

```bash
# Only networking layer
helmfile -l layer=networking sync

# Only observability
helmfile -l layer=observability sync

# Only security
helmfile -l layer=security sync
```

### Destroy All

```bash
helmfile destroy
```

## Configuration

### Values Files

| File | Description |
|------|-------------|
| `values/common.yaml` | Shared settings across environments |
| `values/dev.yaml` | Development environment |
| `values/staging.yaml` | Staging environment |
| `values/prod.yaml` | Production environment |
| `values/traefik.yaml` | Traefik base configuration |

### Secrets

Secrets are stored in `secrets/<env>.yaml` and are gitignored by default.

```bash
# Copy the example
cp secrets/dev.yaml.example secrets/dev.yaml

# Edit with your secrets
vim secrets/dev.yaml
```

For production, consider using:
- **SOPS**: Encrypted secrets in git
- **External Secrets Operator**: Secrets from AWS/GCP/Vault
- **Sealed Secrets**: Encrypted secrets for GitOps

## Releases

### Core (00-core.yaml)

| Release | Chart | Description |
|---------|-------|-------------|
| reloader | stakater/reloader | Auto-restart pods on config changes |

### Networking (10-networking.yaml)

| Release | Chart | Description |
|---------|-------|-------------|
| traefik | traefik/traefik | Ingress controller with NLB |

### Security (20-security.yaml)

| Release | Chart | Description |
|---------|-------|-------------|
| cert-manager | jetstack/cert-manager | TLS certificate automation |
| external-dns | kubernetes-sigs/external-dns | DNS record management |

### Observability (30-observability.yaml)

| Release | Chart | Description |
|---------|-------|-------------|
| prometheus | prometheus-community/kube-prometheus-stack | Monitoring stack |
| loki | grafana/loki | Log aggregation |
| promtail | grafana/promtail | Log collection |

### GitOps (40-gitops.yaml)

| Release | Chart | Description |
|---------|-------|-------------|
| argocd | argo/argo-cd | GitOps CD platform |

## Environment Variables

Each environment can configure:

```yaml
# Cluster identity
clusterName: "exystem-dev"
domain: "dev.example.com"

# Feature flags
observability:
  enabled: true

externalDns:
  enabled: true

argocd:
  enabled: false

# Component settings
traefik:
  replicas: 2

prometheus:
  retentionDays: 15
  storageSize: "50Gi"

loki:
  retentionDays: 30
```

## Secrets Reference

Required secrets (in `secrets/<env>.yaml`):

```yaml
# Cloudflare (for cert-manager and external-dns)
cloudflareApiToken: "..."
cloudflareZoneId: "..."

# ACME (Let's Encrypt)
acme:
  email: "admin@example.com"

# Optional
grafana:
  adminPassword: ""  # Auto-generated if empty
```

## Post-Deployment Setup

### Create Cloudflare Secret

```bash
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token=<your-token>

kubectl create secret generic cloudflare-api-token \
  -n external-dns \
  --from-literal=api-token=<your-token>
```

### Create Wildcard Certificate

```bash
kubectl apply -f manifests/wildcard-certificate.yaml
```

### Verify Deployment

```bash
# Check all pods
kubectl get pods -A

# Check ingresses
kubectl get ingress -A

# Check certificates
kubectl get certificates -A
```

## Troubleshooting

### Traefik not getting external IP

```bash
kubectl get svc -n traefik
kubectl describe svc traefik -n traefik
```

### Certificates not issuing

```bash
kubectl describe certificate wildcard-cert -n traefik
kubectl logs -n cert-manager -l app=cert-manager
```

### External-DNS not creating records

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

### Prometheus not scraping

```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access http://localhost:9090/targets
```
