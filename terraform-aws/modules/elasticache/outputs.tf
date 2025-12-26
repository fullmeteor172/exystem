output "endpoint" {
  description = "Primary endpoint for the ElastiCache cluster"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint for the ElastiCache cluster"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Port for the ElastiCache cluster"
  value       = 6379
}

output "security_group_id" {
  description = "ID of the ElastiCache security group"
  value       = aws_security_group.elasticache.id
}
