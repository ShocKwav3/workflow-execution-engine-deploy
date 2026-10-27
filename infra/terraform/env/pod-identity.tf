data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid       = "ReadRdsMasterSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "ReadAppParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.pghost.arn, aws_ssm_parameter.redis_url.arn]
  }

  # ESO finds the RDS secret by name prefix; listing and batch reads cannot be limited to one secret.
  statement {
    sid       = "FindSecrets"
    actions   = ["secretsmanager:ListSecrets", "secretsmanager:BatchGetSecretValue"]
    resources = ["*"]
  }
}

locals {
  pod_identities = {
    lb_controller = {
      name            = "wee-lb-controller"
      description     = "AWS Load Balancer Controller in the wee cluster"
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      # The policy of the controller release that cluster-addons installs; update both together.
      # The boundary removes iam:ListServerCertificates and iam:GetServerCertificate; only TLS listeners with IAM certificates need them.
      policy = file("${path.module}/files/lb-controller-iam-policy-v3.6.1.json")
    }
    eso = {
      name            = "wee-eso"
      description     = "External Secrets Operator in the wee cluster"
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy          = data.aws_iam_policy_document.eso.json
    }
  }
}

resource "aws_iam_policy" "pod_identity" {
  for_each = local.pod_identities

  name        = "${each.value.name}-policy"
  path        = local.iam_path
  description = each.value.description
  policy      = each.value.policy
}

resource "aws_iam_role" "pod_identity" {
  for_each = local.pod_identities

  name                 = "${each.value.name}-role"
  path                 = local.iam_path
  permissions_boundary = local.iam_boundary_arn
  description          = each.value.description
  assume_role_policy   = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "pod_identity" {
  for_each = local.pod_identities

  role       = aws_iam_role.pod_identity[each.key].name
  policy_arn = aws_iam_policy.pod_identity[each.key].arn
}

resource "aws_eks_pod_identity_association" "main" {
  for_each = local.pod_identities

  cluster_name    = aws_eks_cluster.main.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.pod_identity[each.key].arn
}
