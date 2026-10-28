data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name                 = "wee-eks-cluster-role"
  path                 = local.iam_path
  permissions_boundary = local.iam_boundary_arn
  description          = "EKS control plane role for the wee cluster"
  assume_role_policy   = data.aws_iam_policy_document.cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = "wee"
  version  = "1.36"
  role_arn = aws_iam_role.cluster.arn

  # The add-ons are EKS managed add-ons instead, as in the console.
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # EKS needs the policy while it creates and deletes the cluster.
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

data "aws_iam_role" "admin" {
  name = "AccountFullAccessRole"
}

data "aws_iam_role" "terraform_plan" {
  name = "wee-terraform-plan"
}

data "aws_iam_role" "terraform_apply" {
  name = "wee-terraform-apply"
}

locals {
  cluster_access = {
    admin = {
      principal_arn = data.aws_iam_role.admin.arn
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    terraform_apply = {
      principal_arn = data.aws_iam_role.terraform_apply.arn
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    terraform_plan = {
      principal_arn = data.aws_iam_role.terraform_plan.arn
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    }
  }
}

resource "aws_eks_access_entry" "main" {
  for_each = local.cluster_access

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
}

resource "aws_eks_access_policy_association" "main" {
  for_each = local.cluster_access

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.main[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = "cluster"
  }
}
