#!/bin/bash
set -e

################################################################################
# EKS Cluster Setup Script
#
# Initializes a new cluster with proper state isolation for multi-cluster support.
# Each cluster gets its own state file based on project_name/environment.
#
# Usage:
#   ./setup.sh                        # Interactive mode
#   ./setup.sh myproject staging      # Direct mode
#   ./setup.sh myproject staging -y   # Skip confirmation
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_PROFILE="${AWS_PROFILE:-morpheus}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-tf-state-meteor}"
AWS_REGION="${AWS_REGION:-us-west-2}"

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Parse arguments
PROJECT_NAME="${1:-}"
ENVIRONMENT="${2:-}"
AUTO_CONFIRM="${3:-}"

# Interactive mode if no arguments provided
if [[ -z "$PROJECT_NAME" ]]; then
    print_header "EKS Cluster Setup"

    # Check for existing clusters
    echo -e "Checking for existing cluster configurations..."
    if [[ -f "terraform.tfvars" ]]; then
        existing_project=$(grep -E "^project_name" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
        existing_env=$(grep -E "^environment" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
        if [[ -n "$existing_project" && -n "$existing_env" ]]; then
            print_warning "Found existing config: ${existing_project}-${existing_env}"
            echo ""
        fi
    fi

    read -p "Project name (e.g., exystem, myapp): " PROJECT_NAME
    read -p "Environment (e.g., dev, staging, prod): " ENVIRONMENT
fi

# Validate inputs
if [[ -z "$PROJECT_NAME" || -z "$ENVIRONMENT" ]]; then
    print_error "Project name and environment are required"
    echo "Usage: $0 <project_name> <environment> [-y]"
    exit 1
fi

# Construct cluster name and state key
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate"

print_header "Cluster Configuration"

echo "  Project:     ${PROJECT_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  State Key:   s3://${TF_STATE_BUCKET}/${STATE_KEY}"
echo "  Region:      ${AWS_REGION}"
echo ""

# Check if state already exists
if AWS_PROFILE="${AWS_PROFILE}" aws s3 ls "s3://${TF_STATE_BUCKET}/${STATE_KEY}" --region "${AWS_REGION}" 2>/dev/null; then
    print_warning "State file already exists at s3://${TF_STATE_BUCKET}/${STATE_KEY}"
    echo "  This cluster may already be provisioned."
    echo ""
fi

# Confirm
if [[ "$AUTO_CONFIRM" != "-y" ]]; then
    read -p "Proceed with setup? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

print_header "Initializing Terraform"

# Clean previous state if switching clusters
if [[ -f ".terraform/terraform.tfstate" ]]; then
    current_key=$(cat .terraform/terraform.tfstate 2>/dev/null | jq -r '.backend.config.key // empty' 2>/dev/null || echo "")
    if [[ -n "$current_key" && "$current_key" != "$STATE_KEY" ]]; then
        print_warning "Switching from ${current_key} to ${STATE_KEY}"
        echo "  Clearing local terraform cache..."
        rm -rf .terraform .terraform.lock.hcl
    fi
fi

# Initialize with correct backend
AWS_PROFILE="${AWS_PROFILE}" terraform init \
    -backend-config="key=${STATE_KEY}" \
    -reconfigure

print_header "Creating terraform.tfvars"

# Create or update terraform.tfvars
if [[ -f "terraform.tfvars" ]]; then
    # Update existing file
    sed -i "s/^project_name.*/project_name = \"${PROJECT_NAME}\"/" terraform.tfvars
    sed -i "s/^environment.*/environment  = \"${ENVIRONMENT}\"/" terraform.tfvars
    print_success "Updated terraform.tfvars"
else
    # Copy from example
    if [[ -f "terraform.tfvars.example" ]]; then
        cp terraform.tfvars.example terraform.tfvars
        sed -i "s/^project_name.*/project_name = \"${PROJECT_NAME}\"/" terraform.tfvars
        sed -i "s/^environment.*/environment  = \"${ENVIRONMENT}\"/" terraform.tfvars
        print_success "Created terraform.tfvars from example"
    else
        # Create minimal tfvars
        cat > terraform.tfvars << EOF
project_name = "${PROJECT_NAME}"
environment  = "${ENVIRONMENT}"
aws_region   = "${AWS_REGION}"
domain_name  = "example.com"
acme_email   = "admin@example.com"
EOF
        print_success "Created minimal terraform.tfvars"
    fi
fi

print_header "Setup Complete"

echo "Your cluster '${CLUSTER_NAME}' is ready to be provisioned."
echo ""
echo "Next steps:"
echo "  1. Edit terraform.tfvars to configure your cluster"
echo "  2. Run: terraform plan"
echo "  3. Run: terraform apply"
echo ""
echo "To destroy this cluster later:"
echo "  ./cleanup.sh"
echo "  # or"
echo "  PROJECT_NAME=${PROJECT_NAME} ENVIRONMENT=${ENVIRONMENT} ./cleanup.sh"
echo ""
echo "To switch to a different cluster:"
echo "  ./setup.sh <other_project> <other_env>"
