# Secure-by-default S3 bucket.
#
# Everything a reviewer would otherwise have to remember is on by default:
# encryption with a rotating customer-managed KMS key, all public access
# blocked, ACLs disabled, TLS 1.2+ enforced by policy, versioning, and cleanup
# of abandoned multipart uploads. Callers can relax only what they opt out of.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  create_kms_key = var.kms_key_arn == null && var.create_kms_key
  kms_key_arn    = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  use_kms        = local.kms_key_arn != null

  # Statements that can't be removed: no plain HTTP and no TLS older than 1.2.
  baseline_statements = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    },
    {
      Sid       = "DenyOutdatedTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
    },
  ]
  additional_statements = var.additional_policy_json == null ? [] : tolist(jsondecode(var.additional_policy_json).Statement)
}

# ---- Encryption key ----------------------------------------------------------------

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encrypts objects in s3://${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_key_deletion_window_in_days

  # Account-level administration through IAM; no other principal gets access here.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${replace(var.bucket_name, ".", "-")}"
  target_key_id = aws_kms_key.this[0].key_id
}

# ---- Bucket --------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_144:Cross-region replication is a cost/DR decision for the caller, not a module default
  #checkov:skip=CKV2_AWS_62:Event notifications depend on the caller's architecture
  #checkov:skip=CKV_AWS_18:Access logging is optional (access_logging) because the log bucket itself must not log to itself
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced" # ACLs off: access is decided by policy alone
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = local.use_kms # fewer KMS calls, lower cost
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.baseline_statements, local.additional_statements)
  })

  # Applying a policy before public access is blocked could briefly expose the bucket.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  #checkov:skip=CKV_AWS_300:The first rule always aborts incomplete uploads bucket-wide (see tests); Checkov ignores static rules when a dynamic "rule" block is also present
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days == null ? [] : [rule.value.expiration_days]
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days == null ? [] : [rule.value.noncurrent_version_expiration_days]
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }
    }
  }

  # Lifecycle rules on noncurrent versions need versioning configured first.
  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logging == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = coalesce(var.access_logging.target_prefix, "${var.bucket_name}/")
}
