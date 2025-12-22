################################################################################
# ElastiCache Subnet Group
################################################################################

resource "aws_elasticache_subnet_group" "main" {
  name       = var.cluster_id
  subnet_ids = var.subnet_ids

  tags = var.tags
}

################################################################################
# ElastiCache Security Group
################################################################################

resource "aws_security_group" "elasticache" {
  name        = "${var.cluster_id}-elasticache"
  description = "Security group for ElastiCache cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_id}-elasticache"
    }
  )
}

resource "aws_security_group_rule" "elasticache_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.elasticache.id
  source_security_group_id = var.allowed_security_group_ids[0]
  description              = "Redis access from EKS nodes"
}

resource "aws_security_group_rule" "elasticache_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.elasticache.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

################################################################################
# ElastiCache Parameter Group
################################################################################

resource "aws_elasticache_parameter_group" "main" {
  name   = var.cluster_id
  family = var.parameter_group_family

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = var.tags
}

################################################################################
# ElastiCache Replication Group (Cluster Mode Disabled)
################################################################################

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = var.cluster_id
  replication_group_description = "Redis cluster for ${var.cluster_id}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  number_cache_clusters = var.num_cache_nodes
  parameter_group_name = aws_elasticache_parameter_group.main.name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  automatic_failover_enabled = var.automatic_failover && var.num_cache_nodes > 1
  multi_az_enabled           = var.automatic_failover && var.num_cache_nodes > 1

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled         = false

  snapshot_retention_limit = 5
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "mon:05:00-mon:07:00"

  notification_topic_arn = null

  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = var.tags
}
