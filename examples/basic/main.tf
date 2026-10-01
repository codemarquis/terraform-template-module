# The smallest useful call: every security control is on by default.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "bucket" {
  source = "../../"

  bucket_name = "example-app-assets-123456789012"

  tags = {
    Project   = "example"
    ManagedBy = "terraform"
  }
}

output "bucket_arn" {
  value = module.bucket.bucket_arn
}

output "kms_key_arn" {
  value = module.bucket.kms_key_arn
}
