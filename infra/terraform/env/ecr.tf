locals {
  ecr_repositories = toset(["api", "outbox-relay", "executor", "migrate"])
}

resource "aws_ecr_repository" "app" {
  #checkov:skip=CKV_AWS_136:AES256 encryption at rest; a customer-managed key adds cost per key

  for_each = local.ecr_repositories

  name                 = "workflow-engine/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  # The registry lives only during a session, so destroy removes it with its images.
  force_delete = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# One push stores a tagged index and two untagged manifests, so tagged and untagged objects need separate rules.
data "aws_ecr_lifecycle_policy_document" "app" {
  rule {
    priority    = 1
    description = "Keep the 2 newest tagged images"

    selection {
      tag_status       = "tagged"
      tag_pattern_list = ["*"]
      count_type       = "imageCountMoreThan"
      count_number     = 2
    }

    action {
      type = "expire"
    }
  }

  rule {
    priority    = 2
    description = "Expire untagged images after 1 day"

    selection {
      tag_status   = "untagged"
      count_type   = "sinceImagePushed"
      count_unit   = "days"
      count_number = 1
    }

    action {
      type = "expire"
    }
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name
  policy     = data.aws_ecr_lifecycle_policy_document.app.json
}
