output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret in which RDS keeps the master user credentials."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "rds_endpoint" {
  description = "Host name of the RDS PostgreSQL instance."
  value       = aws_db_instance.main.address
}

output "redis_endpoint" {
  description = "Host name of the primary endpoint of the ElastiCache Redis replication group."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}
