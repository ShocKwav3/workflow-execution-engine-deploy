data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  state_bucket_name = "wee-tfstate-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:access logs need a second bucket; versioning keeps the state history
  #checkov:skip=CKV2_AWS_62:no consumer for bucket events
  #checkov:skip=CKV_AWS_144:one region; cross-region replication doubles storage for a learning project
  #checkov:skip=CKV_AWS_145:SSE-S3 encryption at rest; a customer-managed key adds cost and no access boundary here

  bucket           = local.state_bucket_name
  bucket_namespace = "account-regional"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Versioning keeps every old state file; old versions expire after 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Parts of an interrupted upload are billed but invisible; 1 day is the smallest unit S3 accepts.
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# An account-wide setting, so it lives here and not with the repositories that each session destroys.
resource "aws_ecr_account_setting" "blob_mounting" {
  name  = "BLOB_MOUNTING"
  value = "ENABLED"
}
