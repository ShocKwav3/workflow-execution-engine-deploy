# The state bucket was created by hand before Terraform could store state anywhere.

import {
  to = aws_s3_bucket.state
  id = local.state_bucket_name
}

import {
  to = aws_s3_bucket_versioning.state
  id = local.state_bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.state
  id = local.state_bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.state
  id = local.state_bucket_name
}
