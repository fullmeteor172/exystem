################################################################################
# SSH Key Pair
################################################################################

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.name}-bastion"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-bastion"
    }
  )
}

resource "aws_secretsmanager_secret" "bastion_key" {
  name_prefix = "${var.name}-bastion-key-"
  description = "SSH private key for ${var.name} bastion host"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "bastion_key" {
  secret_id     = aws_secretsmanager_secret.bastion_key.id
  secret_string = tls_private_key.bastion.private_key_pem
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-bastion"
    }
  )
}

resource "aws_security_group_rule" "bastion_ssh_ingress" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion.id
  cidr_blocks       = var.allowed_ssh_cidrs
  description       = "SSH access from allowed CIDRs"
}

resource "aws_security_group_rule" "bastion_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.bastion.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

################################################################################
# IAM Role for SSM and EFS access
################################################################################

resource "aws_iam_role" "bastion" {
  name = "${var.name}-bastion"

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

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_role_policy" "bastion_efs" {
  name = "${var.name}-bastion-efs"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name

  tags = var.tags
}

################################################################################
# EC2 Instance
################################################################################

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.bastion.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = concat([aws_security_group.bastion.id], var.additional_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    efs_id         = var.efs_id
    efs_mount_path = var.efs_mount_path
    cluster_name   = var.name
  }))

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-bastion"
    }
  )

  lifecycle {
    ignore_changes = [ami]
  }
}

################################################################################
# EFS Security Group Rule
################################################################################

resource "aws_security_group_rule" "efs_ingress_from_bastion" {
  count = var.enable_efs ? 1 : 0

  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = var.efs_security_group_id
  source_security_group_id = aws_security_group.bastion.id
  description              = "NFS access from bastion host"
}
