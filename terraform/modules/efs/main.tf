################################################################################
# EFS File System
################################################################################

resource "aws_efs_file_system" "main" {
  creation_token   = var.name
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode
  encrypted        = true

  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

################################################################################
# EFS Security Group
################################################################################

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-efs"
    }
  )
}

resource "aws_security_group_rule" "efs_ingress" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = var.allowed_security_group_ids[0]
  description              = "NFS access from EKS nodes"
}

resource "aws_security_group_rule" "efs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.efs.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

################################################################################
# EFS Mount Targets
################################################################################

resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

################################################################################
# EFS Backup Policy
################################################################################

resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}
