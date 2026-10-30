resource "aws_elasticache_subnet_group" "main" {
  name        = "wee-cache-private"
  description = "Private subnets for ElastiCache"
  subnet_ids  = [for subnet in aws_subnet.private : subnet.id]
}

# BullMQ needs noeviction; a default parameter group cannot be changed.
resource "aws_elasticache_parameter_group" "redis" {
  name        = "wee-redis7-noeviction"
  family      = "redis7"
  description = "Redis OSS 7, maxmemory-policy noeviction for BullMQ"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  #checkov:skip=CKV_AWS_31:TLS in transit is on; the RBAC user follows in a separate change
  #checkov:skip=CKV_AWS_191:at-rest encryption with the AWS-managed key; a customer-managed key adds cost per key
  #checkov:skip=CKV2_AWS_50:one node; Multi-AZ failover doubles the cost; cost; the environment lives only during a session

  replication_group_id = "wee-redis"
  description          = "Redis OSS for BullMQ"

  engine = "redis"
  # From version 7, ElastiCache needs major.minor; patch versions come with auto minor upgrades.
  engine_version       = "7.1"
  node_type            = "cache.t4g.micro"
  cluster_mode         = "disabled"
  num_cache_clusters   = 1
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  multi_az_enabled           = false
  automatic_failover_enabled = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  network_type       = "ipv4"
  port               = 6379

  # The provider default for redis is false, and it cannot change after creation.
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  snapshot_retention_limit = 0
}

resource "aws_ssm_parameter" "redis_url" {
  #checkov:skip=CKV2_AWS_34:holds the host and port only, no secret

  name  = "/wee/app/REDIS_URL"
  type  = "String"
  value = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}
