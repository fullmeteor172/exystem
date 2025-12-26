#!/bin/bash
set -e

################################################################################
# Unified Deployment Script
#
# Deploys infrastructure (Terraform) and workloads (Helmfile) in sequence.
#
# Usage:
#   ./deploy.sh                     # Deploy everything
#   ./deploy.sh --infra-only        # Deploy only infrastructure
#   ./deploy.sh --workloads-only    # Deploy only workloads
#   ./deploy.sh --env staging       # Deploy to staging environment
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default options
DEPLOY_INFRA=true
DEPLOY_WORKLOADS=true
ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
    case $1 in
        --infra-only)
            DEPLOY_WORKLOADS=false
            shift
            ;;
        --workloads-only)
            DEPLOY_INFRA=false
            shift
            ;;
        --env|-e)
            ENVIRONMENT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

print_header "Exystem Deployment - Environment: ${ENVIRONMENT}"

################################################################################
# Step 1: Infrastructure (Terraform)
################################################################################

if [[ "$DEPLOY_INFRA" == "true" ]]; then
    print_header "Step 1: Infrastructure (Terraform)"

    cd "$ROOT_DIR/terraform-aws"

    if [[ ! -f "terraform.tfvars" ]]; then
        print_error "terraform.tfvars not found. Copy terraform.tfvars.example and configure it."
        exit 1
    fi

    echo "Initializing Terraform..."
    terraform init -input=false

    echo "Planning infrastructure changes..."
    terraform plan -out=tfplan

    echo "Applying infrastructure changes..."
    terraform apply tfplan
    rm -f tfplan

    # Configure kubectl
    print_success "Infrastructure deployed"
    eval $(terraform output -raw configure_kubectl)
    print_success "kubectl configured"

    cd "$ROOT_DIR"
fi

################################################################################
# Step 2: Workloads (Helmfile)
################################################################################

if [[ "$DEPLOY_WORKLOADS" == "true" ]]; then
    print_header "Step 2: Workloads (Helmfile)"

    cd "$ROOT_DIR/charts"

    if [[ ! -f "secrets/${ENVIRONMENT}.yaml" ]]; then
        print_warning "secrets/${ENVIRONMENT}.yaml not found."
        print_warning "Copy secrets/${ENVIRONMENT}.yaml.example and configure it."
        print_warning "Some releases may fail without proper secrets."
    fi

    echo "Updating Helm repositories..."
    helmfile repos

    echo "Previewing changes..."
    helmfile -e "$ENVIRONMENT" diff || true

    echo "Deploying workloads..."
    helmfile -e "$ENVIRONMENT" sync

    print_success "Workloads deployed"

    cd "$ROOT_DIR"
fi

################################################################################
# Complete
################################################################################

print_header "Deployment Complete"

echo "Next steps:"
echo "  1. Verify nodes:     kubectl get nodes"
echo "  2. Check workloads:  kubectl get pods -A"
echo "  3. View ingresses:   kubectl get ingress -A"
echo ""

if [[ "$DEPLOY_WORKLOADS" == "true" ]]; then
    echo "Access points:"
    echo "  - Grafana:  https://grafana.${ENVIRONMENT}.example.com"
    echo "  - ArgoCD:   https://argocd.${ENVIRONMENT}.example.com (if enabled)"
fi
