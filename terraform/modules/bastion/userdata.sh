#!/bin/bash
set -ex

# Log all output
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Bastion Host Setup for ${cluster_name} ==="

# Update system
dnf update -y

# Install required packages
dnf install -y \
    amazon-efs-utils \
    nfs-utils \
    jq \
    git \
    htop \
    tree

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install AWS CLI v2 (if not present)
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

%{ if efs_id != "" ~}
# Mount EFS
echo "=== Mounting EFS: ${efs_id} ==="

# Create mount point
mkdir -p ${efs_mount_path}

# Add to fstab for persistence
echo "${efs_id}:/ ${efs_mount_path} efs _netdev,tls,iam 0 0" >> /etc/fstab

# Mount EFS (with retry logic)
for i in {1..5}; do
    mount ${efs_mount_path} && break
    echo "Mount attempt $i failed, retrying in 10s..."
    sleep 10
done

# Verify mount
if mountpoint -q ${efs_mount_path}; then
    echo "EFS mounted successfully at ${efs_mount_path}"
    df -h ${efs_mount_path}
else
    echo "WARNING: EFS mount failed"
fi
%{ endif ~}

# Create helpful aliases for ec2-user
cat >> /home/ec2-user/.bashrc << 'EOF'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kga='kubectl get all -A'

# EFS
%{ if efs_id != "" ~}
alias efs='cd ${efs_mount_path}'
%{ endif ~}

# Show cluster info on login
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bastion Host: ${cluster_name}"
%{ if efs_id != "" ~}
echo "  EFS Mount: ${efs_mount_path}"
%{ endif ~}
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
EOF

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/.bashrc

echo "=== Bastion setup complete ==="
