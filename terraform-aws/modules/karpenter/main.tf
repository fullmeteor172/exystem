################################################################################
# EKS Managed Node Group for Karpenter
# This ensures reliable initial nodes for Karpenter to run on
################################################################################

resource "aws_eks_node_group" "karpenter_initial" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-karpenter-initial"
  node_role_arn   = var.node_iam_role_arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.initial_desired_size
    max_size     = var.initial_max_size
    min_size     = var.initial_min_size
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = [var.initial_instance_type]
  capacity_type  = "ON_DEMAND"

  labels = {
    "node.kubernetes.io/lifecycle" = "on-demand"
    "node.kubernetes.io/nodegroup" = "karpenter-initial"
  }

  tags = merge(
    var.tags,
    {
      Name                     = "${var.cluster_name}-karpenter-initial"
      "karpenter.sh/discovery" = var.cluster_name
    }
  )

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

################################################################################
# Karpenter Helm Release
################################################################################

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = var.namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.6.0"

  create_namespace = true

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  depends_on = [
    aws_eks_node_group.karpenter_initial,
    time_sleep.wait_for_node_cleanup
  ]

  values = [
    yamlencode({
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = var.queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.irsa_arn
        }
      }
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "node.kubernetes.io/nodegroup"
                    operator = "In"
                    values   = ["karpenter-initial"]
                  }
                ]
              }
            ]
          }
        }
      }
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
      replicas = 2
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
    })
  ]
}

################################################################################
# Karpenter EC2NodeClass
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2023"
      role      = var.node_iam_role_name

      subnetSelectorTerms = [
        for subnet_id in var.subnet_ids : {
          id = subnet_id
        }
      ]

      securityGroupSelectorTerms = [
        for sg_id in var.security_group_ids : {
          id = sg_id
        }
      ]

      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]

      tags = merge(
        var.tags,
        {
          Name                     = "${var.cluster_name}-karpenter-node"
          "karpenter.sh/discovery" = var.cluster_name
        }
      )

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "100Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

################################################################################
# Karpenter NodePool
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "node.kubernetes.io/node-pool" = "default"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.capacity_types
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.instance_types
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            }
          ]
          taints = []
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30m"
        budgets = [
          {
            nodes = "10%"
          }
        ]
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}

################################################################################
# Karpenter Node Cleanup on Destroy
################################################################################

resource "null_resource" "karpenter_node_cleanup" {
  triggers = {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up Karpenter-provisioned nodes for cluster: ${self.triggers.cluster_name}"

      INSTANCE_IDS=$(aws ec2 describe-instances \
        --region ${self.triggers.aws_region} \
        --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
                  "Name=tag:karpenter.sh/discovery,Values=${self.triggers.cluster_name}" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null || echo "")

      if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
        echo "Found Karpenter nodes to terminate: $INSTANCE_IDS"
        aws ec2 terminate-instances \
          --region ${self.triggers.aws_region} \
          --instance-ids $INSTANCE_IDS

        echo "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated \
          --region ${self.triggers.aws_region} \
          --instance-ids $INSTANCE_IDS || true

        echo "Karpenter nodes terminated successfully"
      else
        echo "No Karpenter-provisioned nodes found to clean up"
      fi
    EOT
  }
}

resource "time_sleep" "wait_for_node_cleanup" {
  depends_on = [null_resource.karpenter_node_cleanup]

  destroy_duration = "30s"
}
