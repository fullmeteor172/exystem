#!/bin/bash
set -e

################################################################################
# Complete Infrastructure Cleanup Script
#
# Safely destroys all resources created by this Terraform configuration.
# Handles orphaned AWS resources and state cleanup.
#
# Usage:
#   ./cleanup.sh                    # Interactive mode
#   ./cleanup.sh -y                 # Skip confirmation prompts
#   ./cleanup.sh -y --reset-state   # Also reset terraform state
################################################################################

export PAGER=cat
export AWS_PAGER=""
export TF_CLI_ARGS="-no-color"
export TF_INPUT=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AUTO_CONFIRM=false
RESET_STATE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --reset-state)
            RESET_STATE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-y|--yes] [--reset-state]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f "terraform.tfvars" ]]; then
    TFVARS_PROJECT=$(grep -E "^project_name" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
    TFVARS_ENV=$(grep -E "^environment" terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "")
fi

PROJECT_NAME="${PROJECT_NAME:-${TFVARS_PROJECT:-exystem}}"
ENVIRONMENT="${ENVIRONMENT:-${TFVARS_ENV:-dev}}"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
AWS_REGION="${AWS_REGION:-us-west-2}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-tf-state-meteor}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-terraform-locks}"

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

print_header "Infrastructure Cleanup: ${CLUSTER_NAME}"

echo "Configuration:"
echo "  Cluster:      ${CLUSTER_NAME}"
echo "  Region:       ${AWS_REGION}"
echo "  State Bucket: ${TF_STATE_BUCKET}"
echo ""

if [[ "$AUTO_CONFIRM" != "true" ]]; then
    echo -e "${YELLOW}WARNING: This will destroy ALL resources including:${NC}"
    echo "  - EKS cluster and all workloads"
    echo "  - RDS databases (if enabled)"
    echo "  - ElastiCache clusters (if enabled)"
    echo "  - EFS file systems (if enabled)"
    echo "  - Bastion host (if enabled)"
    echo "  - VPC and networking"
    echo ""
    read -p "Type 'destroy' to proceed: " confirm
    if [[ "$confirm" != "destroy" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

print_header "Step 1: Pre-cleanup (Disable RDS deletion protection)"

echo "  Checking for RDS instances with deletion protection..."
aws rds describe-db-instances --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".DBInstances[] | select(.DBInstanceIdentifier | startswith(\"$CLUSTER_NAME\")) | .DBInstanceIdentifier" | \
    while read -r db; do
        if [[ -n "$db" ]]; then
            echo "    Disabling deletion protection: $db"
            aws rds modify-db-instance \
                --db-instance-identifier "$db" \
                --no-deletion-protection \
                --apply-immediately \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
print_success "Pre-destroy preparation complete"

print_header "Step 2: Terraform Destroy"

DESTROY_ATTEMPTS=0
MAX_ATTEMPTS=3

while [[ $DESTROY_ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
    DESTROY_ATTEMPTS=$((DESTROY_ATTEMPTS + 1))
    echo "  Destroy attempt $DESTROY_ATTEMPTS of $MAX_ATTEMPTS..."

    if terraform destroy -auto-approve -input=false -no-color -parallelism=20 2>&1; then
        print_success "Terraform destroy complete"
        break
    else
        if [[ $DESTROY_ATTEMPTS -lt $MAX_ATTEMPTS ]]; then
            print_warning "Destroy failed. Refreshing state and retrying..."
            terraform refresh -input=false -no-color 2>/dev/null || true
            sleep 5
        else
            print_error "Terraform destroy failed after $MAX_ATTEMPTS attempts"
            print_warning "Continuing with orphaned resource cleanup..."
        fi
    fi
done

print_header "Step 3: Orphaned Resource Cleanup"

echo "  Checking for orphaned load balancers..."
aws elbv2 describe-load-balancers --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".LoadBalancers[] | select(.LoadBalancerName | (contains(\"$CLUSTER_NAME\") or contains(\"k8s-\"))) | .LoadBalancerArn" | \
    while read -r arn; do
        [[ -n "$arn" ]] && {
            echo "    Deleting: $arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

echo "  Checking for orphaned target groups..."
aws elbv2 describe-target-groups --region "$AWS_REGION" 2>/dev/null | \
    jq -r '.TargetGroups[] | select(.TargetGroupName | contains("k8s-")) | .TargetGroupArn' | \
    while read -r arn; do
        [[ -n "$arn" ]] && {
            echo "    Deleting: $arn"
            aws elbv2 delete-target-group --target-group-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

print_success "Orphaned resource cleanup complete"

if [[ "$RESET_STATE" == "true" ]]; then
    print_header "Step 4: State Reset"

    STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/"
    echo "  Clearing state at: s3://${TF_STATE_BUCKET}/${STATE_KEY}"
    aws s3 rm "s3://${TF_STATE_BUCKET}/${STATE_KEY}" --recursive 2>/dev/null || true

    echo "  Cleaning local cache..."
    rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup

    print_success "State reset complete"
fi

print_header "Cleanup Complete"

echo "To provision a new cluster:"
echo "  terraform init && terraform apply"
echo ""
