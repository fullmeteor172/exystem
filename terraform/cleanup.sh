#!/bin/bash
set -e

################################################################################
# Complete Infrastructure Cleanup Script
#
# Safely destroys all resources created by this Terraform configuration.
# Handles Kubernetes resources, orphaned AWS resources, and state cleanup.
#
# Usage:
#   ./cleanup.sh                    # Interactive mode
#   ./cleanup.sh -y                 # Skip confirmation prompts
#   ./cleanup.sh -y --reset-state   # Also reset terraform state
#
# Environment Variables:
#   PROJECT_NAME    - Project name (default: from terraform.tfvars or "exystem")
#   ENVIRONMENT     - Environment (default: from terraform.tfvars or "dev")
#   AWS_REGION      - AWS region (default: "us-west-2")
#   AWS_PROFILE     - AWS profile (default: "morpheus")
################################################################################

# Disable pagers and interactive prompts
export PAGER=cat
export AWS_PAGER=""
export TF_CLI_ARGS="-no-color"
export TF_INPUT=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
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

# Configuration - try to read from terraform.tfvars first
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
AWS_PROFILE="${AWS_PROFILE:-morpheus}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-tf-state-meteor}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-terraform-locks}"

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
    echo "  - All S3 data (except Terraform state bucket)"
    echo ""
    read -p "Type 'destroy' to proceed: " confirm
    if [[ "$confirm" != "destroy" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

################################################################################
# Step 1: Kubernetes Resources Cleanup
################################################################################

print_header "Step 1: Kubernetes Resources Cleanup"

if AWS_PROFILE="$AWS_PROFILE" aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" &>/dev/null; then
    print_success "Cluster found. Cleaning up Kubernetes resources..."

    # Update kubeconfig
    AWS_PROFILE="$AWS_PROFILE" aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

    # Delete Helm releases
    echo "  Deleting Helm releases..."
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
        releases=$(helm list -n "$ns" -q 2>/dev/null || echo "")
        for release in $releases; do
            echo "    Uninstalling: $ns/$release"
            helm uninstall "$release" -n "$ns" --wait=false 2>/dev/null || true
        done
    done

    # Delete ingresses (removes load balancers)
    echo "  Deleting ingress resources..."
    kubectl delete ingress --all --all-namespaces --wait=false 2>/dev/null || true

    # Delete LoadBalancer services
    echo "  Deleting LoadBalancer services..."
    kubectl get svc --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read -r ns name; do
            [[ -n "$ns" && -n "$name" ]] && kubectl delete svc "$name" -n "$ns" --wait=false 2>/dev/null || true
        done

    # Remove PVC finalizers and delete
    echo "  Cleaning up PVCs..."
    kubectl get pvc --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read -r ns name; do
            [[ -n "$ns" && -n "$name" ]] && {
                kubectl patch pvc "$name" -n "$ns" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
                kubectl delete pvc "$name" -n "$ns" --wait=false 2>/dev/null || true
            }
        done

    # Remove PV finalizers and delete
    echo "  Cleaning up PVs..."
    kubectl get pv -o json 2>/dev/null | \
        jq -r '.items[].metadata.name' | \
        while read -r name; do
            [[ -n "$name" ]] && {
                kubectl patch pv "$name" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
                kubectl delete pv "$name" --wait=false 2>/dev/null || true
            }
        done

    echo "  Waiting for resources to terminate..."
    sleep 10
    print_success "Kubernetes cleanup complete"
else
    print_warning "Cluster not accessible. Skipping Kubernetes cleanup."
fi

################################################################################
# Step 2: Empty S3 Buckets
################################################################################

print_header "Step 2: S3 Bucket Cleanup"

for bucket in $(AWS_PROFILE="$AWS_PROFILE" aws s3 ls 2>/dev/null | awk '{print $3}' | grep -E "^${CLUSTER_NAME}" || echo ""); do
    if [[ "$bucket" != "$TF_STATE_BUCKET" ]]; then
        echo "  Emptying bucket: $bucket"
        AWS_PROFILE="$AWS_PROFILE" aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true

        # Delete versions if versioning is enabled
        AWS_PROFILE="$AWS_PROFILE" aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
            jq -r '.Versions[]? | "\(.Key)\t\(.VersionId)"' | \
            while IFS=$'\t' read -r key version; do
                [[ -n "$key" && -n "$version" ]] && \
                    AWS_PROFILE="$AWS_PROFILE" aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            done

        AWS_PROFILE="$AWS_PROFILE" aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
            jq -r '.DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
            while IFS=$'\t' read -r key version; do
                [[ -n "$key" && -n "$version" ]] && \
                    AWS_PROFILE="$AWS_PROFILE" aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            done
    fi
done
print_success "S3 cleanup complete"

################################################################################
# Step 3: Disable RDS Deletion Protection
################################################################################

print_header "Step 3: Prepare for Terraform Destroy"

echo "  Checking for RDS instances with deletion protection..."
AWS_PROFILE="$AWS_PROFILE" aws rds describe-db-instances --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".DBInstances[] | select(.DBInstanceIdentifier | startswith(\"$CLUSTER_NAME\")) | .DBInstanceIdentifier" | \
    while read -r db; do
        if [[ -n "$db" ]]; then
            echo "    Disabling deletion protection: $db"
            AWS_PROFILE="$AWS_PROFILE" aws rds modify-db-instance \
                --db-instance-identifier "$db" \
                --no-deletion-protection \
                --apply-immediately \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
print_success "Pre-destroy preparation complete"

################################################################################
# Step 4: Terraform Destroy
################################################################################

print_header "Step 4: Terraform Destroy"

DESTROY_ATTEMPTS=0
MAX_ATTEMPTS=3

while [[ $DESTROY_ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
    DESTROY_ATTEMPTS=$((DESTROY_ATTEMPTS + 1))
    echo "  Destroy attempt $DESTROY_ATTEMPTS of $MAX_ATTEMPTS..."

    if AWS_PROFILE="$AWS_PROFILE" terraform destroy -auto-approve -input=false -no-color -parallelism=20 2>&1; then
        print_success "Terraform destroy complete"
        break
    else
        if [[ $DESTROY_ATTEMPTS -lt $MAX_ATTEMPTS ]]; then
            print_warning "Destroy failed. Refreshing state and retrying..."
            AWS_PROFILE="$AWS_PROFILE" terraform refresh -input=false -no-color 2>/dev/null || true
            sleep 5
        else
            print_error "Terraform destroy failed after $MAX_ATTEMPTS attempts"
            print_warning "Continuing with orphaned resource cleanup..."
        fi
    fi
done

################################################################################
# Step 5: Cleanup Orphaned AWS Resources
################################################################################

print_header "Step 5: Orphaned Resource Cleanup"

# Load Balancers
echo "  Checking for orphaned load balancers..."
AWS_PROFILE="$AWS_PROFILE" aws elbv2 describe-load-balancers --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".LoadBalancers[] | select(.LoadBalancerName | (contains(\"$CLUSTER_NAME\") or contains(\"k8s-\"))) | .LoadBalancerArn" | \
    while read -r arn; do
        [[ -n "$arn" ]] && {
            echo "    Deleting: $arn"
            AWS_PROFILE="$AWS_PROFILE" aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

# Target Groups
echo "  Checking for orphaned target groups..."
AWS_PROFILE="$AWS_PROFILE" aws elbv2 describe-target-groups --region "$AWS_REGION" 2>/dev/null | \
    jq -r '.TargetGroups[] | select(.TargetGroupName | contains("k8s-")) | .TargetGroupArn' | \
    while read -r arn; do
        [[ -n "$arn" ]] && {
            echo "    Deleting: $arn"
            AWS_PROFILE="$AWS_PROFILE" aws elbv2 delete-target-group --target-group-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

# EBS Volumes
echo "  Checking for orphaned EBS volumes..."
AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-volumes --region "$AWS_REGION" --filters "Name=status,Values=available" 2>/dev/null | \
    jq -r '.Volumes[] | select(.Tags[]? | select(.Key | (contains("kubernetes") or contains("karpenter") or contains("'"$CLUSTER_NAME"'")))) | .VolumeId' | \
    sort -u | while read -r vol; do
        [[ -n "$vol" ]] && {
            echo "    Deleting: $vol"
            AWS_PROFILE="$AWS_PROFILE" aws ec2 delete-volume --volume-id "$vol" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

# Elastic IPs
echo "  Checking for orphaned Elastic IPs..."
AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-addresses --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".Addresses[] | select(.Tags[]?.Value | contains(\"$CLUSTER_NAME\")) | select(.AssociationId == null) | .AllocationId" | \
    while read -r eip; do
        [[ -n "$eip" ]] && {
            echo "    Releasing: $eip"
            AWS_PROFILE="$AWS_PROFILE" aws ec2 release-address --allocation-id "$eip" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

# Security Groups (after dependencies are cleared)
sleep 5
echo "  Checking for orphaned security groups..."
AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-security-groups --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".SecurityGroups[] | select(.GroupName | (contains(\"$CLUSTER_NAME\") or contains(\"k8s-\"))) | select(.GroupName != \"default\") | .GroupId" | \
    while read -r sg; do
        [[ -n "$sg" ]] && {
            echo "    Deleting: $sg"
            # Clear rules first
            AWS_PROFILE="$AWS_PROFILE" aws ec2 revoke-security-group-ingress --group-id "$sg" \
                --ip-permissions "$(AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null)" \
                --region "$AWS_REGION" 2>/dev/null || true
            AWS_PROFILE="$AWS_PROFILE" aws ec2 revoke-security-group-egress --group-id "$sg" \
                --ip-permissions "$(AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null)" \
                --region "$AWS_REGION" 2>/dev/null || true
            AWS_PROFILE="$AWS_PROFILE" aws ec2 delete-security-group --group-id "$sg" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

# Network Interfaces
echo "  Checking for orphaned network interfaces..."
AWS_PROFILE="$AWS_PROFILE" aws ec2 describe-network-interfaces --region "$AWS_REGION" --filters "Name=status,Values=available" 2>/dev/null | \
    jq -r ".NetworkInterfaces[] | select(.Description | (contains(\"$CLUSTER_NAME\") or contains(\"ELB\") or contains(\"kubernetes\"))) | .NetworkInterfaceId" | \
    while read -r eni; do
        [[ -n "$eni" ]] && {
            echo "    Deleting: $eni"
            AWS_PROFILE="$AWS_PROFILE" aws ec2 delete-network-interface --network-interface-id "$eni" --region "$AWS_REGION" 2>/dev/null || true
        }
    done

print_success "Orphaned resource cleanup complete"

################################################################################
# Step 6: State Reset (Optional)
################################################################################

if [[ "$RESET_STATE" == "true" ]]; then
    print_header "Step 6: State Reset"

    STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/"
    echo "  Clearing state at: s3://${TF_STATE_BUCKET}/${STATE_KEY}"
    AWS_PROFILE="$AWS_PROFILE" aws s3 rm "s3://${TF_STATE_BUCKET}/${STATE_KEY}" --recursive 2>/dev/null || true

    echo "  Clearing DynamoDB locks..."
    AWS_PROFILE="$AWS_PROFILE" aws dynamodb scan --table-name "$TF_LOCK_TABLE" --projection-expression "LockID" 2>/dev/null | \
        jq -r '.Items[].LockID.S' | grep "$PROJECT_NAME" | \
        while read -r lock; do
            [[ -n "$lock" ]] && {
                echo "    Deleting: $lock"
                AWS_PROFILE="$AWS_PROFILE" aws dynamodb delete-item --table-name "$TF_LOCK_TABLE" --key "{\"LockID\": {\"S\": \"$lock\"}}" 2>/dev/null || true
            }
        done

    echo "  Cleaning local cache..."
    rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup

    print_success "State reset complete"
else
    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        echo ""
        read -p "Reset Terraform state? (yes/no): " reset_state
        if [[ "$reset_state" == "yes" ]]; then
            STATE_KEY="${PROJECT_NAME}/${ENVIRONMENT}/"
            echo "  Clearing state..."
            AWS_PROFILE="$AWS_PROFILE" aws s3 rm "s3://${TF_STATE_BUCKET}/${STATE_KEY}" --recursive 2>/dev/null || true
            rm -rf .terraform .terraform.lock.hcl terraform.tfstate.backup
            print_success "State reset complete"
        fi
    fi
fi

################################################################################
# Complete
################################################################################

print_header "Cleanup Complete"

echo "Preserved resources:"
echo "  - S3 Bucket: $TF_STATE_BUCKET (state storage)"
echo "  - DynamoDB Table: $TF_LOCK_TABLE (lock table)"
echo ""
echo "To provision a new cluster:"
echo "  ./setup.sh"
echo ""
