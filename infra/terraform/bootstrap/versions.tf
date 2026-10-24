terraform {
  required_version = ">= 1.15.0"

  # The bucket name holds the account ID, so `terraform init -backend-config="bucket=..."` passes it in.
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}
