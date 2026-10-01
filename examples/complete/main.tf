# A data bucket with lifecycle tiering, sending access logs to a dedicated
# log bucket. Both buckets come from this module.

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

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  data_name  = "example-data-${local.account_id}"
  logs_name  = "example-access-logs-${local.account_id}"
  tags = {
    Project   = "example"
    ManagedBy = "terraform"
  }
}

# S3 server access logs can only be delivered to a bucket using SSE-S3, and
# the logging service needs permission to write there, scoped to our account
# and our data bucket.
data "aws_iam_policy_document" "log_delivery" {
  statement {
    sid       = "AllowS3ServerAccessLogs"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.logs_name}/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${local.data_name}"]
    }
  }
}

module "access_logs" {
  source = "../../"

  bucket_name            = local.logs_name
  create_kms_key         = false # log delivery requires SSE-S3
  additional_policy_json = data.aws_iam_policy_document.log_delivery.json

  lifecycle_rules = [{
    id                                 = "expire-access-logs"
    expiration_days                    = 90
    noncurrent_version_expiration_days = 7
  }]

  tags = local.tags
}

module "data" {
  source = "../../"

  bucket_name = local.data_name

  access_logging = {
    target_bucket = module.access_logs.bucket_id
  }

  lifecycle_rules = [
    {
      id = "tier-down"
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 180, storage_class = "GLACIER_IR" },
      ]
      noncurrent_version_expiration_days = 90
    },
    {
      id              = "expire-tmp"
      prefix          = "tmp/"
      expiration_days = 7
    },
  ]

  tags = local.tags
}

output "data_bucket" {
  value = {
    arn         = module.data.bucket_arn
    kms_key_arn = module.data.kms_key_arn
  }
}

output "log_bucket" {
  value = module.access_logs.bucket_id
}
