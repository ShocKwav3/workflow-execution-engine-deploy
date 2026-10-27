locals {
  cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "rds" {
  name        = "wee-rds"
  description = "RDS PostgreSQL; inbound 5432 from the EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "wee-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_cluster" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from EKS cluster wee"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = local.cluster_security_group_id
}

resource "aws_security_group" "redis" {
  name        = "wee-redis"
  description = "ElastiCache Redis; inbound 6379 from the EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "wee-redis"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_cluster" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from EKS cluster wee"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = local.cluster_security_group_id
}

# The LB controller finds this group by its Name tag (Service annotation).
resource "aws_security_group" "nlb" {
  name        = "wee-nlb"
  description = "NLB for the api; inbound 80 from the operator IP only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "wee-nlb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_operator" {
  security_group_id = aws_security_group.nlb.id
  description       = "operator"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.operator_cidr
}

# Terraform removes the default allow-all egress rule; the NLB needs it to reach the Pods.
resource "aws_vpc_security_group_egress_rule" "nlb_all" {
  security_group_id = aws_security_group.nlb.id
  description       = "all traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
