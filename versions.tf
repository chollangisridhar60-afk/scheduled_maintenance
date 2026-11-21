terraform {
  backend "s3" {
    bucket = "tfstate-707582904453-us-west-2-scheduled-maintenance"
    # key is supplied at init, one state per region:
    #   terraform init -backend-config="key=scheduled-maintenance/<region>/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true # S3 native locking (Terraform >= 1.10), no DynamoDB needed
  }

  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
