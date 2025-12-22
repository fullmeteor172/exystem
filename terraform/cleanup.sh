#!/bin/bash
set -e

echo "🧹 Complete AWS Infrastructure Cleanup Script"
echo "=============================================="
echo ""
echo "⚠️  WARNING: This will destroy ALL resources created by Terraform"
echo "This includes EKS cluster, RDS, ElastiCache, networking, etc."
echo ""
read -p "Are you sure you want to continue? Type 'yes' to proceed: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

PROJECT_NAME="exystem"
ENVIRONMENT="dev"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
AWS_REGION="us-west-2"

echo ""
echo "Step 1: Cleaning up Kubernetes resources..."
echo "=============================================="

# Configure kubectl if needed
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME \
  --role-arn arn:aws:iam::143495498599:role/terraform-admin 2>/dev/null || true

# Delete all ingress resources (removes load balancers)
echo "Deleting ingress resources..."
kubectl delete ingress --all --all-namespaces 2>/dev/null || true

# Delete all services of type LoadBalancer
echo "Deleting LoadBalancer services..."
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer 2>/dev/null || true

# Delete all PVCs (removes EBS volumes)
echo "Deleting PersistentVolumeClaims..."
kubectl delete pvc --all --all-namespaces 2>/dev/null || true

echo "Waiting 60 seconds for AWS resources to be cleaned up..."
sleep 60

echo ""
echo "Step 2: Emptying S3 buckets..."
echo "=============================================="

# Empty Loki logs bucket
LOKI_BUCKET="${CLUSTER_NAME}-loki-logs"
if aws s3 ls "s3://${LOKI_BUCKET}" 2>/dev/null; then
    echo "Emptying ${LOKI_BUCKET}..."
    aws s3 rm "s3://${LOKI_BUCKET}" --recursive || true
fi

echo ""
echo "Step 3: Running Terraform destroy..."
echo "=============================================="

terraform destroy -auto-approve

echo ""
echo "Step 4: Checking for orphaned resources..."
echo "=============================================="

echo "Checking for orphaned load balancers..."
ORPHAN_ELBS=$(aws elbv2 describe-load-balancers --region $AWS_REGION \
  --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "$ORPHAN_ELBS" ]; then
    echo "⚠️  Found orphaned load balancers:"
    echo "$ORPHAN_ELBS"
    echo ""
    read -p "Delete these load balancers? (yes/no): " delete_lbs
    if [ "$delete_lbs" = "yes" ]; then
        for lb_arn in $ORPHAN_ELBS; do
            echo "Deleting $lb_arn..."
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region $AWS_REGION
        done
    fi
fi

echo "Checking for orphaned EBS volumes..."
ORPHAN_VOLS=$(aws ec2 describe-volumes --region $AWS_REGION \
  --filters "Name=status,Values=available" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
  --query "Volumes[].VolumeId" --output text 2>/dev/null || true)

if [ -n "$ORPHAN_VOLS" ]; then
    echo "⚠️  Found orphaned EBS volumes:"
    echo "$ORPHAN_VOLS"
    echo ""
    read -p "Delete these volumes? (yes/no): " delete_vols
    if [ "$delete_vols" = "yes" ]; then
        for vol_id in $ORPHAN_VOLS; do
            echo "Deleting $vol_id..."
            aws ec2 delete-volume --volume-id "$vol_id" --region $AWS_REGION
        done
    fi
fi

echo "Checking for orphaned Elastic IPs..."
ORPHAN_EIPS=$(aws ec2 describe-addresses --region $AWS_REGION \
  --filters "Name=tag:Name,Values=${CLUSTER_NAME}*" \
  --query "Addresses[?AssociationId==null].AllocationId" \
  --output text 2>/dev/null || true)

if [ -n "$ORPHAN_EIPS" ]; then
    echo "⚠️  Found orphaned Elastic IPs:"
    echo "$ORPHAN_EIPS"
    echo ""
    read -p "Release these Elastic IPs? (yes/no): " delete_eips
    if [ "$delete_eips" = "yes" ]; then
        for eip_id in $ORPHAN_EIPS; do
            echo "Releasing $eip_id..."
            aws ec2 release-address --allocation-id "$eip_id" --region $AWS_REGION
        done
    fi
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Check AWS Console for any remaining resources"
echo "2. Verify no unexpected charges in AWS Cost Explorer"
echo "3. The S3 state bucket (tf-state-meteor) was NOT deleted"
echo ""
