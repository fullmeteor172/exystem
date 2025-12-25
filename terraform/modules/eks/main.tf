################################################################################
# EKS Cluster
################################################################################

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    security_group_ids      = [aws_security_group.cluster.id]
  }

  # Enable new authentication mode for access entries
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = var.tags
}

################################################################################
# EKS Cluster IAM Role
################################################################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

################################################################################
# EKS Cluster Security Group
################################################################################

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

resource "aws_security_group_rule" "cluster_egress_internet" {
  description       = "Allow cluster egress access to the Internet"
  protocol          = "-1"
  security_group_id = aws_security_group.cluster.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  type              = "egress"
}

################################################################################
# Node Security Group
################################################################################

resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for all nodes in the cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-node-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      "karpenter.sh/discovery"                    = var.cluster_name
    }
  )
}

resource "aws_security_group_rule" "node_ingress_self" {
  description              = "Allow nodes to communicate with each other"
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
  from_port                = 0
  to_port                  = 0
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_ingress_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  from_port                = 1025
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_ingress_cluster_443" {
  description              = "Allow pods running extension API servers to receive communication from cluster control plane"
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "cluster_ingress_node_443" {
  description              = "Allow pods to communicate with the cluster API Server"
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_egress_internet" {
  description       = "Allow nodes egress access to the Internet"
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  type              = "egress"
}

################################################################################
# OIDC Provider for IRSA
################################################################################

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# Note: Cluster creator admin permissions are now handled by
# access_config.bootstrap_cluster_creator_admin_permissions in the cluster resource

################################################################################
# Karpenter IAM Role for Service Account (IRSA)
################################################################################

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"
  role = aws_iam_role.karpenter_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = aws_eks_cluster.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/*"
      }
    ]
  })
}

################################################################################
# Karpenter Node IAM Role
################################################################################

resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name

  tags = var.tags
}

################################################################################
# Karpenter SQS Queue for Interruption Handling
################################################################################

resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

################################################################################
# EventBridge Rules for Karpenter Interruption Handling
################################################################################

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${var.cluster_name}-karpenter-spot-interruption"
  description = "Karpenter spot instance interruption warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${var.cluster_name}-karpenter-rebalance"
  description = "Karpenter rebalance recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  name        = "${var.cluster_name}-karpenter-instance-state-change"
  description = "Karpenter instance state change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change" {
  name        = "${var.cluster_name}-karpenter-scheduled-change"
  description = "Karpenter scheduled change"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_scheduled_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter.arn
}

################################################################################
# EBS CSI Driver IRSA
################################################################################

resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}
