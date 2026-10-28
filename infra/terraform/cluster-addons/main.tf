data "aws_region" "current" {}

# The env config creates the cluster; reading it by name needs no access to the env state.
data "aws_eks_cluster" "main" {
  name = "wee"
}
