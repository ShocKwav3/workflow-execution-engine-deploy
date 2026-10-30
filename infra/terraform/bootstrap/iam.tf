resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:actor_id"
      values   = [var.github_actor_id]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "wee-terraform-plan"
  path               = "/ci/"
  description        = "Runs terraform plan from pull requests of the config repository."
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess already reads the state; plan also writes the lock file.
data "aws_iam_policy_document" "plan_state_lock" {
  statement {
    sid       = "WriteLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_state_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state_lock.json
}

locals {
  managed_iam_arn_prefix = "arn:aws:iam::${data.aws_caller_identity.current.account_id}"
  apply_boundary_arn     = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:aws"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:actor_id"
      values   = [var.github_actor_id]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "wee-terraform-apply"
  path               = "/ci/"
  description        = "Runs terraform apply and destroy from the aws environment of the config repository."
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

resource "aws_iam_role_policy_attachment" "apply_read_only" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "apply" {
  #checkov:skip=CKV_AWS_356:service-level wildcards by design (ADR-110); created roles are capped by the PowerUserAccess boundary
  #checkov:skip=CKV_AWS_109:IAM actions limited to the /wee/ path and the boundary condition (ADR-110)
  #checkov:skip=CKV_AWS_111:the apply role must create and delete the env resources (ADR-110)
  #checkov:skip=CKV_AWS_107:credential actions are needed for the env resources; limited by the boundary (ADR-110)
  #checkov:skip=CKV_AWS_108:read access is needed to plan and apply (ADR-110)

  statement {
    sid = "ManageServices"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "elasticache:*",
      "ecr:*",
      "secretsmanager:*",
      "ssm:*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteState"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*/terraform.tfstate"]
  }

  statement {
    sid       = "WriteLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*/terraform.tfstate.tflock"]
  }

  statement {
    sid = "ChangeRolePermissionsOnlyWithBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["${local.managed_iam_arn_prefix}:role/wee/*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.apply_boundary_arn]
    }
  }

  statement {
    sid = "ManageRoles"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["${local.managed_iam_arn_prefix}:role/wee/*"]
  }

  statement {
    sid = "ManagePolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["${local.managed_iam_arn_prefix}:policy/wee/*"]
  }

  statement {
    sid       = "CreateServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
