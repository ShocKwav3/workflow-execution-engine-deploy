data "aws_region" "current" {}

# The CI apply role can create roles only under this path and with this boundary.
locals {
  iam_path         = "/wee/"
  iam_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
