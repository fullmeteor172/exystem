# Kubernetes Workloads (Helmfile)

Deploy Kubernetes workloads across multiple environments using Helmfile.

## Table of Contents

1. [Directory Structure](#directory-structure)
2. [Complete Deployment Workflow](#complete-deployment-workflow)
3. [How Values and Secrets Flow](#how-values-and-secrets-flow)
4. [Adding Your Own Applications](#adding-your-own-applications)
5. [ArgoCD GitOps Setup](#argocd-gitops-setup)
6. [Component Reference](#component-reference)
7. [Commands Reference](#commands-reference)
8. [Troubleshooting](#troubleshooting)

---

## Directory Structure

```
charts/
├── helmfile.yaml              # Main orchestrator - defines environments
├── helmfile.d/                # Layered release definitions (deploy order)
│   ├── 00-core.yaml           # Reloader (auto-restart on config change)
│   ├── 10-networking.yaml     # Traefik ingress controller
│   ├── 20-security.yaml       # Cert-manager, External-DNS
│   ├── 30-observability.yaml  # Prometheus, Grafana, Loki, Promtail
│   ├── 40-gitops.yaml         # ArgoCD
│   └── 50-apps.yaml           # YOUR applications go here
│
├── environments/              # All configuration per environment
│   ├── common/
│   │   └── values.yaml        # Shared values (Cloudflare IPs, defaults)
│   ├── dev/
│   │   ├── values.yaml        # Dev config (replicas, retention, apps)
│   │   └── secrets.yaml       # Dev secrets (gitignored!)
│   ├── staging/
│   │   ├── values.yaml
│   │   └── secrets.yaml
│   └── prod/
│       ├── values.yaml
│       └── secrets.yaml
│
├── apps/                      # Your custom Helm charts
│   └── example/               # Example app with all features
│       ├── Chart.yaml
│       ├── values.yaml        # Chart defaults
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── pvc.yaml       # EFS/NFS storage
│           └── secrets.yaml   # DB/Redis credentials
│
├── argocd/                    # ArgoCD ApplicationSets
│   └── platform-apps.yaml     # Auto-sync from GitHub
│
└── manifests/                 # Raw K8s manifests
    └── cluster-issuer.yaml
```

---

## Complete Deployment Workflow

### Step 1: Create Infrastructure (Terraform)

```bash
cd terraform-aws

# Configure your environment
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Set project_name, region, etc.

# Deploy infrastructure
terraform init
terraform plan
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### Step 2: Configure Chart Values

```bash
cd charts

# Copy secrets template for your environment
cp environments/dev/secrets.yaml.example environments/dev/secrets.yaml

# Edit secrets (Cloudflare token, etc.)
vim environments/dev/secrets.yaml

# Edit values (domain, cluster name)
vim environments/dev/values.yaml
```

**Required changes in `values.yaml`:**
```yaml
clusterName: "my-cluster-dev"
domain: "dev.yourdomain.com"
```

**Required secrets in `secrets.yaml`:**
```yaml
cloudflare:
  apiToken: "your-cloudflare-api-token"
acme:
  email: "admin@yourdomain.com"
```

### Step 3: Create Kubernetes Secrets

```bash
# Cloudflare token for cert-manager (TLS certificates)
kubectl create namespace cert-manager
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token=<your-cloudflare-token>

# Cloudflare token for external-dns (DNS records)
kubectl create namespace external-dns
kubectl create secret generic cloudflare-api-token \
  -n external-dns \
  --from-literal=api-token=<your-cloudflare-token>
```

### Step 4: Deploy Platform Charts

```bash
cd charts

# Add Helm repositories
helmfile repos

# Preview what will be deployed
helmfile -e dev diff

# Deploy everything
helmfile -e dev sync
```

### Step 5: Deploy Your Applications

```bash
# Enable example app in environments/dev/values.yaml
apps:
  example:
    enabled: true

# Deploy just your app
helmfile -e dev -l component=example sync

# Or deploy everything
helmfile -e dev sync
```

---

## How Values and Secrets Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        helmfile.yaml                                 │
│  environments:                                                       │
│    dev:                                                              │
│      values:                                                         │
│        - environments/common/values.yaml    ─┐                      │
│        - environments/dev/values.yaml        ├── Merged in order    │
│      secrets:                                │                       │
│        - environments/dev/secrets.yaml      ─┘                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Merged .Values available to all helmfile.d/*.yaml files            │
│                                                                      │
│  .Values.domain           = "dev.example.com"                       │
│  .Values.clusterName      = "exystem-dev"                           │
│  .Values.components.traefik = true                                  │
│  .Values.apps.example.enabled = true                                │
│  .Values.apps.example.database.password = "secret" (from secrets)   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  helmfile.d/50-apps.yaml                                            │
│                                                                      │
│  - name: example-app                                                 │
│    condition: apps.example.enabled   ← Only deploys if true         │
│    values:                                                           │
│      - ingress:                                                      │
│          host: {{ .Values.apps.example.ingress.host }}              │
│        database:                                                     │
│          password: {{ .Values.apps.example.database.password }}     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  apps/example/templates/deployment.yaml                              │
│                                                                      │
│  env:                                                                │
│    - name: DATABASE_PASSWORD                                         │
│      valueFrom:                                                      │
│        secretKeyRef:                                                 │
│          name: example-app-secrets  ← K8s Secret created by chart   │
│          key: database-password                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Value Precedence (later wins)

1. `environments/common/values.yaml` - Defaults for all environments
2. `environments/<env>/values.yaml` - Environment-specific overrides
3. `environments/<env>/secrets.yaml` - Sensitive values (gitignored)
4. `apps/<app>/values.yaml` - Chart defaults (lowest priority)

---

## Adding Your Own Applications

### Method 1: Helmfile (Recommended for Platform)

#### Step 1: Create Your Chart

```bash
# Copy example chart
cp -r apps/example apps/my-app

# Edit chart metadata
vim apps/my-app/Chart.yaml
```

#### Step 2: Add Release to 50-apps.yaml

```yaml
# helmfile.d/50-apps.yaml
releases:
  - name: my-app
    namespace: my-app
    createNamespace: true
    chart: ../apps/my-app
    labels:
      layer: apps
      component: my-app
    condition: apps.myApp.enabled
    values:
      - replicaCount: {{ .Values.apps.myApp.replicas | default 2 }}
        image:
          repository: {{ .Values.apps.myApp.image.repository }}
          tag: {{ .Values.apps.myApp.image.tag | default "latest" }}
        ingress:
          enabled: {{ .Values.apps.myApp.ingress.enabled | default false }}
          host: my-app.{{ .Values.domain }}
        database:
          enabled: {{ .Values.apps.myApp.database.enabled | default false }}
          host: {{ .Values.apps.myApp.database.host | default "" }}
          password: {{ .Values.apps.myApp.database.password | default "" }}
```

#### Step 3: Add Values to Environment

```yaml
# environments/dev/values.yaml
apps:
  myApp:
    enabled: true
    replicas: 1
    image:
      repository: myregistry/my-app
      tag: "v1.0.0"
    ingress:
      enabled: true
    database:
      enabled: true
      host: "mydb.xxxxx.rds.amazonaws.com"
      name: "myapp"
      username: "myapp"
```

```yaml
# environments/dev/secrets.yaml
apps:
  myApp:
    database:
      password: "super-secret-password"
```

#### Step 4: Deploy

```bash
# Deploy just your app
helmfile -e dev -l component=my-app sync

# Or deploy everything
helmfile -e dev sync
```

### Method 2: ArgoCD (Recommended for Microservices)

See [ArgoCD GitOps Setup](#argocd-gitops-setup) below.

---

## ArgoCD GitOps Setup

ArgoCD watches your Git repository and automatically deploys changes.

### Step 1: Enable ArgoCD

```yaml
# environments/dev/values.yaml (or staging/prod)
components:
  argocd: true
```

```bash
helmfile -e dev -l component=argocd sync
```

### Step 2: Configure Repository Access

```bash
# Get ArgoCD admin password
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
# https://argocd.<your-domain>

# Or port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Visit https://localhost:8080
```

In ArgoCD UI:
1. Go to Settings → Repositories
2. Add your GitHub repository
3. Use SSH key or GitHub App for private repos

### Step 3: Apply ApplicationSet

Edit `argocd/platform-apps.yaml`:

```yaml
# Change these values
repoURL: https://github.com/YOUR_ORG/YOUR_REPO.git
targetRevision: main  # or your branch
```

Apply:
```bash
kubectl apply -f argocd/platform-apps.yaml
```

### How ArgoCD Watches Your Repo

```
GitHub Repository
└── charts/
    ├── apps/
    │   ├── my-app-1/     ← ArgoCD creates Application for each
    │   ├── my-app-2/     ← Watches for changes
    │   └── my-app-3/     ← Auto-syncs on push
    └── environments/
        └── dev/
            └── values.yaml  ← Values passed to each app
```

The `ApplicationSet` in `argocd/platform-apps.yaml`:
- Discovers all directories in `charts/apps/`
- Creates an ArgoCD Application for each
- Watches for Git changes
- Auto-syncs when you push

---

## Component Reference

### Component Toggles

All components can be enabled/disabled in `environments/<env>/values.yaml`:

```yaml
components:
  reloader: true        # Auto-restart pods on ConfigMap/Secret change
  traefik: true         # Ingress controller
  certManager: true     # TLS certificate automation
  externalDns: true     # DNS record automation
  observability: true   # Prometheus, Grafana, Loki, Promtail
  argocd: false         # GitOps (enable in staging/prod)
```

### Platform Components

| Layer | Component | Version | Purpose |
|-------|-----------|---------|---------|
| 00-core | reloader | 1.2.0 | Restart pods on config changes |
| 10-networking | traefik | 32.1.1 | Ingress controller + NLB |
| 20-security | cert-manager | v1.16.2 | TLS certificates from Let's Encrypt |
| 20-security | external-dns | 1.15.0 | DNS records in Cloudflare |
| 30-observability | prometheus | 65.8.1 | Metrics + Alertmanager |
| 30-observability | grafana | (included) | Dashboards |
| 30-observability | loki | 6.22.0 | Log aggregation |
| 30-observability | promtail | 6.16.6 | Log collection |
| 40-gitops | argocd | 7.7.5 | GitOps CD |

### Environment Defaults

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Traefik replicas | 1 | 2 | 3 |
| Prometheus retention | 7d | 15d | 30d |
| Prometheus storage | 20Gi | 30Gi | 100Gi |
| Loki retention | 7d | 15d | 30d |
| ArgoCD enabled | No | Yes | Yes |
| Example app replicas | 1 | 2 | 3 |

---

## Commands Reference

### Deploy Commands

```bash
# Deploy to environment
helmfile -e dev sync
helmfile -e staging sync
helmfile -e prod sync

# Preview changes (dry-run)
helmfile -e dev diff

# Deploy specific component
helmfile -e dev -l component=traefik sync
helmfile -e dev -l component=prometheus sync
helmfile -e dev -l component=example sync

# Deploy specific layer
helmfile -e dev -l layer=apps sync
helmfile -e dev -l layer=observability sync

# List all releases
helmfile -e dev list
```

### Destroy Commands

```bash
# Destroy all releases
helmfile -e dev destroy

# Destroy specific component
helmfile -e dev -l component=argocd destroy
helmfile -e dev -l component=example destroy
```

### Debugging Commands

```bash
# Template without applying
helmfile -e dev template

# Show values for a release
helmfile -e dev -l component=example write-values
```

---

## Troubleshooting

### Check Overall Status

```bash
kubectl get pods -A | grep -v Running
kubectl get ingress -A
kubectl get certificates -A
```

### Traefik (Ingress)

```bash
kubectl get svc -n traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

### Certificates (TLS)

```bash
kubectl get certificates -A
kubectl describe certificate wildcard-cert -n traefik
kubectl logs -n cert-manager -l app=cert-manager
```

### DNS (External-DNS)

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

### Grafana

```bash
# Get admin password
kubectl get secret -n observability prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

### ArgoCD

```bash
# Get admin password
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Sync an application
argocd app sync <app-name>

# Check app status
argocd app get <app-name>
```

---

## Secrets Management

### Development (Plaintext)

```bash
cp environments/dev/secrets.yaml.example environments/dev/secrets.yaml
# Edit and keep local only - gitignored
```

### Production (SOPS Encrypted)

```bash
# Install SOPS
brew install sops  # or apt install sops

# Create .sops.yaml in repo root
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: environments/.*/secrets\.yaml$
    kms: arn:aws:kms:us-east-1:123456789:key/your-key-id
EOF

# Encrypt secrets
sops -e environments/prod/secrets.yaml.example > environments/prod/secrets.yaml

# Edit encrypted secrets
sops environments/prod/secrets.yaml
```

### From AWS Secrets Manager

For database passwords from Terraform RDS:

```bash
# Get password from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id exystem-dev-rds-credentials \
  --query SecretString --output text | jq -r .password
```

Add to `environments/dev/secrets.yaml`:
```yaml
apps:
  myApp:
    database:
      password: "<paste-password-here>"
```
