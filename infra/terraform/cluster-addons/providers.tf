provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "workflow-engine"
      ManagedBy = "terraform"
      Stack     = "cluster-addons"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

    # EKS tokens expire after minutes, so the provider gets a new one at each run.
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.aws_eks_cluster.main.name, "--region", data.aws_region.current.region]
    }
  }
}
