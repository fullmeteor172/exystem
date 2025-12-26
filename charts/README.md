# Kubernetes Workloads (Helmfile)

Deploy Kubernetes workloads across multiple environments using Helmfile.

## Directory Structure

```
charts/
├── helmfile.yaml              # Main orchestrator
├── helmfile.d/                # Layered release definitions
│   ├── 00-core.yaml           # Reloader
│   ├── 10-networking.yaml     # Traefik ingress
│   ├── 20-security.yaml       # Cert-manager, External-DNS
│   ├── 30-observability.yaml  # Prometheus, Grafana, Loki
│   ├── 40-gitops.yaml         # ArgoCD
│   └── 50-apps.yaml           # Your applications
│
├── environments/              # Environment configurations
│   ├── common/
│   │   └── values.yaml        # Shared values (Cloudflare IPs, defaults)
│   ├── dev/
│   │   ├── values.yaml        # Dev-specific values
│   │   └── secrets.yaml       # Dev secrets (gitignored)
│   ├── staging/
│   │   ├── values.yaml
│   │   └── secrets.yaml
│   └── prod/
│       ├── values.yaml
│       └── secrets.yaml
│
├── apps/                      # Custom application charts
│   └── example/               # Example app template
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│
└── manifests/                 # Raw K8s manifests
    └── cluster-issuer.yaml
```

## Quick Start

### 1. Prerequisites

- kubectl configured for your cluster
- Helm >= 3.x
- Helmfile >= 0.150.0

### 2. Configure Your Environment

```bash
# Copy secrets template
cp environments/dev/secrets.yaml.example environments/dev/secrets.yaml

# Edit with your values
vim environments/dev/secrets.yaml
```

Required secrets:
```yaml
cloudflare:
  apiToken: "your-cloudflare-api-token"
  zoneId: "your-zone-id"

acme:
  email: "admin@yourdomain.com"
```

### 3. Update Domain

Edit `environments/dev/values.yaml`:
```yaml
clusterName: "my-cluster-dev"
domain: "dev.yourdomain.com"
```

### 4. Deploy

```bash
cd charts

# Add helm repos
helmfile repos

# Preview changes
helmfile -e dev diff

# Deploy
helmfile -e dev sync
```

### 5. Create Required Secrets

```bash
# Cloudflare token for cert-manager
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token=<your-token>

# Cloudflare token for external-dns
kubectl create secret generic cloudflare-api-token \
  -n external-dns \
  --from-literal=api-token=<your-token>
```

## Commands

```bash
# Deploy to environment
helmfile -e dev sync
helmfile -e staging sync
helmfile -e prod sync

# Preview changes
helmfile -e dev diff

# Deploy specific component
helmfile -e dev -l component=traefik sync
helmfile -e dev -l component=prometheus sync

# Deploy specific layer
helmfile -e dev -l layer=observability sync

# List releases
helmfile -e dev list

# Destroy all
helmfile -e dev destroy
```

## Component Toggles

Enable/disable components in `environments/<env>/values.yaml`:

```yaml
components:
  reloader: true        # Auto-restart on config changes
  traefik: true         # Ingress controller
  certManager: true     # TLS certificates
  externalDns: true     # DNS automation
  observability: true   # Prometheus/Grafana/Loki
  argocd: false         # GitOps (disabled in dev by default)
```

## Environment Configuration

### Common Values (`environments/common/values.yaml`)

Shared across all environments:
- Cloudflare trusted IP ranges
- Default resource configurations
- Storage class settings

### Environment-Specific Values

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Traefik replicas | 1 | 2 | 3 |
| Prometheus retention | 7d | 15d | 30d |
| Prometheus storage | 20Gi | 30Gi | 100Gi |
| ArgoCD enabled | No | Yes | Yes |

## Adding Custom Applications

### Option 1: Add to 50-apps.yaml

Edit `helmfile.d/50-apps.yaml`:

```yaml
releases:
  - name: my-app
    namespace: my-app
    createNamespace: true
    chart: ../apps/my-app
    labels:
      layer: apps
      component: my-app
    values:
      - image:
          tag: {{ .Values.apps.myApp.imageTag | default "latest" }}
```

Add values in `environments/<env>/values.yaml`:
```yaml
apps:
  myApp:
    imageTag: "v1.0.0"
```

### Option 2: Use ArgoCD

Deploy apps via ArgoCD ApplicationSets for GitOps workflows.

## Secrets Management

### Development

Use plaintext secrets (gitignored):
```bash
cp environments/dev/secrets.yaml.example environments/dev/secrets.yaml
```

### Production

Use SOPS encryption:
```bash
# Install sops
brew install sops

# Create .sops.yaml in repo root
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: environments/.*/secrets\.yaml$
    kms: arn:aws:kms:us-east-1:123456789:key/your-key-id
EOF

# Encrypt secrets
sops -e environments/prod/secrets.yaml.example > environments/prod/secrets.yaml
```

## Component Details

### Core (00-core)
| Release | Version | Description |
|---------|---------|-------------|
| reloader | 1.2.0 | Auto-restarts pods on ConfigMap/Secret changes |

### Networking (10-networking)
| Release | Version | Description |
|---------|---------|-------------|
| traefik | 32.1.1 | Ingress controller with AWS NLB |

### Security (20-security)
| Release | Version | Description |
|---------|---------|-------------|
| cert-manager | v1.16.2 | TLS certificate automation |
| external-dns | 1.15.0 | Cloudflare DNS record management |

### Observability (30-observability)
| Release | Version | Description |
|---------|---------|-------------|
| prometheus | 65.8.1 | Monitoring with kube-prometheus-stack |
| loki | 6.22.0 | Log aggregation |
| promtail | 6.16.6 | Log collection |

### GitOps (40-gitops)
| Release | Version | Description |
|---------|---------|-------------|
| argocd | 7.7.5 | GitOps continuous deployment |

## Accessing Services

### Grafana
```bash
# URL: https://grafana.<your-domain>
# Get admin password (if auto-generated):
kubectl get secret -n observability prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### ArgoCD
```bash
# URL: https://argocd.<your-domain>
# Get initial admin password:
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Troubleshooting

### Check pod status
```bash
kubectl get pods -A | grep -v Running
```

### Traefik issues
```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
kubectl get svc -n traefik
```

### Certificate issues
```bash
kubectl get certificates -A
kubectl describe certificate -n traefik wildcard-cert
kubectl logs -n cert-manager -l app=cert-manager
```

### DNS issues
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

### Prometheus issues
```bash
kubectl port-forward -n observability svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

## Upgrading

```bash
# Update helm repos
helmfile repos

# Preview changes
helmfile -e <env> diff

# Apply updates
helmfile -e <env> sync
```

## Cleanup

```bash
# Destroy all releases in an environment
helmfile -e dev destroy

# Remove specific component
helmfile -e dev -l component=argocd destroy
```
