################################################################################
# AWS EBS CSI Driver
# Essential for persistent storage - stays in Terraform as it's AWS-specific
################################################################################

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = var.ebs_csi_driver_irsa_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = data.aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

################################################################################
# Storage Classes
# These are AWS-specific and tied to the EBS CSI driver
################################################################################

# GP3 Storage Class (default)
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

# GP3 with immediate binding (for StatefulSets that need it)
resource "kubernetes_storage_class" "gp3_immediate" {
  metadata {
    name = "gp3-immediate"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

################################################################################
# EFS CSI Driver (Optional)
# AWS-specific driver for shared storage
################################################################################

resource "helm_release" "efs_csi_driver" {
  count = var.enable_efs ? 1 : 0

  name       = "aws-efs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"
  version    = "3.0.8"

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = true
          name   = "efs-csi-controller-sa"
        }
      }
      storageClasses = [
        {
          name = "efs"
          parameters = {
            provisioningMode = "efs-ap"
            fileSystemId     = var.efs_file_system_id
            directoryPerms   = "700"
          }
          reclaimPolicy     = "Delete"
          volumeBindingMode = "Immediate"
        }
      ]
    })
  ]
}

################################################################################
# Metrics Server
# Essential for HPA and resource metrics - provider agnostic but needed early
################################################################################

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = "3.12.2"

  values = [
    yamlencode({
      args = [
        "--cert-dir=/tmp",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-use-node-status-port",
        "--metric-resolution=15s"
      ]
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    })
  ]
}
