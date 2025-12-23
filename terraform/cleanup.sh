#!/bin/bash
set -e

echo "=== Complete Infrastructure Cleanup ==="
echo ""
echo "WARNING: This will destroy ALL resources including:"
echo "  - EKS cluster and all workloads"
echo "  - RDS databases (if enabled)"
echo "  - ElastiCache clusters (if enabled)"
echo "  - EFS file systems (if enabled)"
echo "  - VPC and networking"
echo "  - All S3 data (except Terraform state)"
echo ""
read -p "Type 'destroy' to proceed: " confirm

if [ "$confirm" != "destroy" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Configuration - update these to match your setup
PROJECT_NAME="${PROJECT_NAME:-exystem}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
AWS_REGION="${AWS_REGION:-us-west-2}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-tf-state-meteor}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-terraform-locks}"

echo ""
echo "=== Step 1: Pre-cleanup Kubernetes resources ==="

# Try to connect to the cluster
if aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" &>/dev/null; then
    echo "Cluster found. Cleaning up Kubernetes resources..."

    # Update kubeconfig
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

    # Delete all Helm releases first (they manage the pods/PVCs)
    echo "Deleting Helm releases..."
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
        helm list -n "$ns" -q 2>/dev/null | xargs -r -I {} helm uninstall {} -n "$ns" --wait=false 2>/dev/null || true
    done

    # Delete ingresses (removes load balancers)
    echo "Deleting ingress resources..."
    kubectl delete ingress --all --all-namespaces --wait=false 2>/dev/null || true

    # Delete LoadBalancer services
    echo "Deleting LoadBalancer services..."
    kubectl get svc --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read ns name; do
            kubectl delete svc "$name" -n "$ns" --wait=false 2>/dev/null || true
        done

    # Force delete stuck PVCs by removing finalizers
    echo "Removing PVC finalizers and deleting PVCs..."
    kubectl get pvc --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read ns name; do
            kubectl patch pvc "$name" -n "$ns" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl delete pvc "$name" -n "$ns" --wait=false 2>/dev/null || true
        done

    # Force delete stuck PVs
    echo "Removing PV finalizers and deleting PVs..."
    kubectl get pv -o json 2>/dev/null | \
        jq -r '.items[].metadata.name' | \
        while read name; do
            kubectl patch pv "$name" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl delete pv "$name" --wait=false 2>/dev/null || true
        done

    echo "Waiting 30 seconds for resources to terminate..."
    sleep 30
else
    echo "Cluster not found or not accessible. Skipping Kubernetes cleanup."
fi

echo ""
echo "=== Step 2: Empty S3 buckets ==="

# Find and empty project-related buckets (excluding state bucket)
for bucket in $(aws s3 ls 2>/dev/null | awk '{print $3}' | grep -E "^${CLUSTER_NAME}" || echo ""); do
    if [ "$bucket" != "$TF_STATE_BUCKET" ]; then
        echo "Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        # Also delete versions if versioning is enabled
        aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
            jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | \
            while read key version; do
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            done
        aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null | \
            jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
            while read key version; do
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            done
    fi
done

echo ""
echo "=== Step 3: Terraform destroy ==="

# Disable deletion protection on RDS if it exists
echo "Disabling RDS deletion protection..."
aws rds describe-db-instances --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".DBInstances[] | select(.DBInstanceIdentifier | startswith(\"$CLUSTER_NAME\")) | .DBInstanceIdentifier" | \
    while read db; do
        echo "Disabling deletion protection for: $db"
        aws rds modify-db-instance --db-instance-identifier "$db" --no-deletion-protection --apply-immediately --region "$AWS_REGION" 2>/dev/null || true
    done

# Run terraform destroy with auto-approve
cd "$(dirname "$0")"
terraform destroy -auto-approve -parallelism=20 2>&1 || {
    echo ""
    echo "Terraform destroy encountered errors. Retrying with refresh..."
    terraform refresh 2>/dev/null || true
    terraform destroy -auto-approve -parallelism=20 -refresh=false 2>&1 || true
}

echo ""
echo "=== Step 4: Cleanup orphaned AWS resources ==="

# Delete orphaned load balancers
echo "Checking for orphaned load balancers..."
aws elbv2 describe-load-balancers --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".LoadBalancers[] | select(.LoadBalancerName | contains(\"$CLUSTER_NAME\") or contains(\"k8s-\")) | .LoadBalancerArn" | \
    while read arn; do
        echo "Deleting load balancer: $arn"
        aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
    done

# Delete orphaned target groups
echo "Checking for orphaned target groups..."
aws elbv2 describe-target-groups --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".TargetGroups[] | select(.TargetGroupName | contains(\"k8s-\")) | .TargetGroupArn" | \
    while read arn; do
        echo "Deleting target group: $arn"
        aws elbv2 delete-target-group --target-group-arn "$arn" --region "$AWS_REGION" 2>/dev/null || true
    done

# Delete orphaned EBS volumes
echo "Checking for orphaned EBS volumes..."
aws ec2 describe-volumes --region "$AWS_REGION" --filters "Name=status,Values=available" 2>/dev/null | \
    jq -r '.Volumes[] | select(.Tags[]? | select(.Key | contains("kubernetes") or contains("karpenter"))) | .VolumeId' | \
    while read vol; do
        echo "Deleting volume: $vol"
        aws ec2 delete-volume --volume-id "$vol" --region "$AWS_REGION" 2>/dev/null || true
    done

# Release orphaned Elastic IPs
echo "Checking for orphaned Elastic IPs..."
aws ec2 describe-addresses --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".Addresses[] | select(.Tags[]?.Value | contains(\"$CLUSTER_NAME\")) | select(.AssociationId == null) | .AllocationId" | \
    while read eip; do
        echo "Releasing Elastic IP: $eip"
        aws ec2 release-address --allocation-id "$eip" --region "$AWS_REGION" 2>/dev/null || true
    done

# Delete orphaned security groups
echo "Checking for orphaned security groups..."
aws ec2 describe-security-groups --region "$AWS_REGION" 2>/dev/null | \
    jq -r ".SecurityGroups[] | select(.GroupName | contains(\"$CLUSTER_NAME\") or contains(\"k8s-\")) | select(.GroupName != \"default\") | .GroupId" | \
    while read sg; do
        echo "Deleting security group: $sg"
        # First remove all ingress/egress rules
        aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$(aws ec2 describe-security-groups --group-ids $sg --query 'SecurityGroups[0].IpPermissions' --output json)" --region "$AWS_REGION" 2>/dev/null || true
        aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions "$(aws ec2 describe-security-groups --group-ids $sg --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" --region "$AWS_REGION" 2>/dev/null || true
        aws ec2 delete-security-group --group-id "$sg" --region "$AWS_REGION" 2>/dev/null || true
    done

# Delete orphaned network interfaces
echo "Checking for orphaned network interfaces..."
aws ec2 describe-network-interfaces --region "$AWS_REGION" --filters "Name=status,Values=available" 2>/dev/null | \
    jq -r ".NetworkInterfaces[] | select(.Description | contains(\"$CLUSTER_NAME\") or contains(\"ELB\") or contains(\"kubernetes\")) | .NetworkInterfaceId" | \
    while read eni; do
        echo "Deleting network interface: $eni"
        aws ec2 delete-network-interface --network-interface-id "$eni" --region "$AWS_REGION" 2>/dev/null || true
    done

echo ""
echo "=== Step 5: Reset Terraform state (optional) ==="
read -p "Reset Terraform state in S3? This allows fresh 'terraform init'. (yes/no): " reset_state

if [ "$reset_state" = "yes" ]; then
    echo "Clearing Terraform state..."
    aws s3 rm "s3://$TF_STATE_BUCKET/${PROJECT_NAME}/" --recursive 2>/dev/null || true

    # Clear DynamoDB locks
    aws dynamodb scan --table-name "$TF_LOCK_TABLE" --projection-expression "LockID" 2>/dev/null | \
        jq -r '.Items[].LockID.S' | grep "$PROJECT_NAME" | \
        while read lock; do
            aws dynamodb delete-item --table-name "$TF_LOCK_TABLE" --key "{\"LockID\": {\"S\": \"$lock\"}}" 2>/dev/null || true
        done

    echo "State reset complete."
fi

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Preserved resources:"
echo "  - S3 Bucket: $TF_STATE_BUCKET"
echo "  - DynamoDB Table: $TF_LOCK_TABLE"
echo ""
echo "Next steps:"
echo "  1. rm -rf .terraform .terraform.lock.hcl"
echo "  2. terraform init"
echo "  3. terraform plan"
echo "  4. terraform apply"
