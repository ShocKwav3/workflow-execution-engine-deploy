provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "workflow-engine"
      ManagedBy = "terraform"
      Stack     = "env"
    }
  }
}
