terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in shared class bucket, unique key per candidate.
  backend "s3" {
    bucket       = "pgr301-terraform-state"
    key          = "wishifai/38/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}
