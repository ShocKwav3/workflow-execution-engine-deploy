resource "aws_db_subnet_group" "main" {
  name        = "wee-db-private"
  description = "Private subnets for RDS"
  subnet_ids  = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_db_instance" "main" {
  #checkov:skip=CKV_AWS_293:deletion protection would block terraform destroy at the end of each session
  #checkov:skip=CKV_AWS_161:the apps use the master user from Secrets Manager; IAM database auth is deferred
  #checkov:skip=CKV_AWS_353:Performance Insights is off; cost; the environment lives only during a session
  #checkov:skip=CKV_AWS_157:single-AZ; Multi-AZ doubles the cost; cost; the environment lives only during a session
  #checkov:skip=CKV_AWS_133:no backups; the data is test data and is destroyed with the session
  #checkov:skip=CKV_AWS_129:log exports bill CloudWatch ingestion; cost; the environment lives only during a session
  #checkov:skip=CKV_AWS_118:enhanced monitoring is off; cost; the environment lives only during a session
  #checkov:skip=CKV2_AWS_30:query logging bills CloudWatch ingestion; cost; the environment lives only during a session

  identifier = "wee-postgres"
  engine     = "postgres"
  # Major version only: RDS applies minor upgrades and retires old minor versions by itself.
  engine_version = "16"
  instance_class = "db.t4g.micro"
  multi_az       = false

  # The provider default is extended support, which bills after the end of standard support.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  db_name  = "workflow_db"
  username = "workflow"
  # RDS creates and rotates the password in Secrets Manager, so it never enters the state.
  manage_master_user_password = true

  storage_type      = "gp3"
  allocated_storage = 20
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  database_insights_mode       = "standard"
  performance_insights_enabled = false
  monitoring_interval          = 0

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
}

resource "aws_ssm_parameter" "pghost" {
  #checkov:skip=CKV2_AWS_34:holds the host name only, no secret

  name  = "/wee/app/PGHOST"
  type  = "String"
  value = aws_db_instance.main.address
}
