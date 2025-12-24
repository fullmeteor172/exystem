#!/bin/bash
set -e

################################################################################
# Enhanced Terraform Plan with Resource Summary
#
# Provides a clean, categorized view of what will be created.
#
# Usage:
#   ./plan.sh              # Show summary + detailed plan
#   ./plan.sh --summary    # Show only summary
#   ./plan.sh --full       # Show only full terraform plan
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

AWS_PROFILE="${AWS_PROFILE:-morpheus}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
SHOW_SUMMARY=true
SHOW_FULL=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --summary)
            SHOW_FULL=false
            shift
            ;;
        --full)
            SHOW_SUMMARY=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Read config from tfvars
if [[ -f "terraform.tfvars" ]]; then
    PROJECT_NAME=$(grep -E "^project_name" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    ENVIRONMENT=$(grep -E "^environment" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    ENABLE_RDS=$(grep -E "^enable_rds" terraform.tfvars 2>/dev/null | grep -oE "(true|false)" || echo "false")
    ENABLE_ELASTICACHE=$(grep -E "^enable_elasticache" terraform.tfvars 2>/dev/null | grep -oE "(true|false)" || echo "false")
    ENABLE_EFS=$(grep -E "^enable_efs" terraform.tfvars 2>/dev/null | grep -oE "(true|false)" || echo "false")
    ENABLE_BASTION=$(grep -E "^enable_bastion" terraform.tfvars 2>/dev/null | grep -oE "(true|false)" || echo "false")
    ENABLE_OBSERVABILITY=$(grep -E "^enable_observability" terraform.tfvars 2>/dev/null | grep -oE "(true|false)" || echo "false")
    DOMAIN_NAME=$(grep -E "^domain_name" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "not set")
    CLUSTER_VERSION=$(grep -E "^cluster_version" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "1.34")
else
    echo "Error: terraform.tfvars not found. Run ./setup.sh first."
    exit 1
fi

CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

feature_status() {
    if [[ "$2" == "true" ]]; then
        echo -e "  ${GREEN}●${NC} $1"
    else
        echo -e "  ${BOLD}○${NC} $1 ${YELLOW}(disabled)${NC}"
    fi
}

if [[ "$SHOW_SUMMARY" == "true" ]]; then
    print_header "Cluster Configuration: ${CLUSTER_NAME}"

    echo -e "${BOLD}Core Settings:${NC}"
    echo "  Cluster Name:      ${CLUSTER_NAME}"
    echo "  Kubernetes:        v${CLUSTER_VERSION}"
    echo "  Domain:            ${DOMAIN_NAME}"
    echo ""

    echo -e "${BOLD}Infrastructure (Always Created):${NC}"
    echo -e "  ${GREEN}●${NC} VPC with 3 public + 3 private subnets"
    echo -e "  ${GREEN}●${NC} NAT Gateway for private subnet egress"
    echo -e "  ${GREEN}●${NC} EKS Control Plane"
    echo -e "  ${GREEN}●${NC} Karpenter node autoscaler (2 initial nodes)"
    echo -e "  ${GREEN}●${NC} Traefik ingress controller"
    echo -e "  ${GREEN}●${NC} Cert-manager with Let's Encrypt"
    echo -e "  ${GREEN}●${NC} EBS CSI driver + Metrics server"
    echo ""

    echo -e "${BOLD}Optional Components:${NC}"
    feature_status "PostgreSQL Database (RDS)" "$ENABLE_RDS"
    feature_status "Redis Cache (ElastiCache)" "$ENABLE_ELASTICACHE"
    feature_status "Shared Storage (EFS)" "$ENABLE_EFS"
    feature_status "Bastion Host" "$ENABLE_BASTION"
    feature_status "Observability (Prometheus/Grafana/Loki)" "$ENABLE_OBSERVABILITY"
    echo ""

    # Run terraform plan and capture output
    print_header "Resource Count by Type"

    echo "Running terraform plan..."
    if ! AWS_PROFILE="$AWS_PROFILE" terraform plan -out=.tfplan -input=false -no-color >/dev/null 2>&1; then
        echo -e "${RED}Error: terraform plan failed. Run 'terraform init' first.${NC}"
        exit 1
    fi

    # Parse and display resource counts
    terraform show -json .tfplan 2>/dev/null | jq -r '
        .resource_changes // [] |
        map(select(.change.actions | contains(["create"]))) |
        group_by(.type) |
        map({type: .[0].type, count: length}) |
        sort_by(.type) |
        .[] |
        "  \(.type | split("_") | .[1:] | join("_")): \(.count)"
    ' | column -t

    rm -f .tfplan
    echo ""

    print_header "Estimated Costs (Monthly)"

    echo "Core Infrastructure:"
    echo "  EKS Control Plane:     ~\$72/mo"
    echo "  NAT Gateway:           ~\$32/mo + data transfer"
    echo "  2x t3.large (initial): ~\$120/mo"
    echo ""
    echo "Optional (if enabled):"
    [[ "$ENABLE_RDS" == "true" ]] && echo "  RDS db.t4g.micro:      ~\$13/mo"
    [[ "$ENABLE_ELASTICACHE" == "true" ]] && echo "  ElastiCache t4g.micro: ~\$12/mo"
    [[ "$ENABLE_EFS" == "true" ]] && echo "  EFS:                   ~\$0.30/GB-mo"
    [[ "$ENABLE_BASTION" == "true" ]] && echo "  Bastion t3.micro:      ~\$8/mo"
    [[ "$ENABLE_OBSERVABILITY" == "true" ]] && echo "  Observability storage: ~\$5/mo (50GB)"
    echo ""
    echo -e "${YELLOW}Note: Actual costs depend on usage. Karpenter nodes are billed based on actual usage.${NC}"
    echo ""
fi

if [[ "$SHOW_FULL" == "true" && "$SHOW_SUMMARY" == "true" ]]; then
    print_header "Detailed Plan"
    echo "Run 'terraform plan' for full details, or 'terraform apply' to proceed."
fi
