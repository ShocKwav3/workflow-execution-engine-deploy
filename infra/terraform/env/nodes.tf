data "aws_iam_policy_document" "node_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name                 = "wee-eks-node-role"
  path                 = local.iam_path
  permissions_boundary = local.iam_boundary_arn
  description          = "EKS node role for the wee cluster"
  assume_role_policy   = data.aws_iam_policy_document.node_trust.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

locals {
  # Nodes stay NotReady without the VPC CNI; CoreDNS Pods need nodes to run on.
  addons_before_nodes = ["vpc-cni", "eks-pod-identity-agent"]
  addons_after_nodes  = ["kube-proxy", "coredns"]
}

data "aws_eks_addon_version" "main" {
  for_each = toset(concat(local.addons_before_nodes, local.addons_after_nodes))

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
}

resource "aws_eks_addon" "before_nodes" {
  for_each = toset(local.addons_before_nodes)

  cluster_name  = aws_eks_cluster.main.name
  addon_name    = each.key
  addon_version = data.aws_eks_addon_version.main[each.key].version
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "wee-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["t4g.small"]
  disk_size      = 20

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  # The failure experiments must not trigger a node replacement.
  node_repair_config {
    enabled = false
  }

  # EKS needs the policies to delete the instances and network interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}

resource "aws_eks_addon" "after_nodes" {
  for_each = toset(local.addons_after_nodes)

  cluster_name  = aws_eks_cluster.main.name
  addon_name    = each.key
  addon_version = data.aws_eks_addon_version.main[each.key].version

  depends_on = [aws_eks_node_group.main]
}
