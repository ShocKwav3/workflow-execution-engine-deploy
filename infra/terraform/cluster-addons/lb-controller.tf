resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  # The IAM policy file in the env config belongs to this version; update both together.
  version   = "3.6.2"
  namespace = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = data.aws_eks_cluster.main.name
    },
    {
      name  = "region"
      value = data.aws_region.current.region
    },
    {
      # Set explicitly, so the controller does not read it from the instance metadata of its node.
      name  = "vpcId"
      value = data.aws_eks_cluster.main.vpc_config[0].vpc_id
    },
    {
      # Must match the Pod Identity association in the env config.
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
  ]
}
