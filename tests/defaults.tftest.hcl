# Secure defaults: what a caller gets by passing only a bucket name.
# Runs against a mocked AWS provider, so no credentials or real resources are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::secure-bucket-test" }
  }
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-central-1:123456789012:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  bucket_name = "secure-bucket-test"
}

run "encrypts_with_a_dedicated_rotating_kms_key" {
  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A customer-managed KMS key with rotation should be created by default."
  }
  assert {
    condition     = jsondecode(aws_kms_key.this[0].policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root"
    error_message = "The key policy should delegate administration to the account's IAM only."
  }
  assert {
    condition     = aws_kms_alias.this[0].name == "alias/s3/secure-bucket-test"
    error_message = "The key should get a readable alias."
  }
  assert {
    condition = one([
      for r in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      r.apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
      && r.apply_server_side_encryption_by_default[0].kms_master_key_id == aws_kms_key.this[0].arn
      && r.bucket_key_enabled
    ])
    error_message = "Default encryption should be SSE-KMS with the created key and S3 Bucket Keys."
  }
  assert {
    condition     = output.encryption == "aws:kms" && output.kms_key_arn == aws_kms_key.this[0].arn
    error_message = "Outputs should report the KMS key in use."
  }
}

run "blocks_all_public_access_and_disables_acls" {
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }
  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs should be disabled (BucketOwnerEnforced)."
  }
}

run "enforces_tls_1_2_by_policy" {
  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTLS"]
    error_message = "The baseline policy should deny plain HTTP and TLS older than 1.2, and nothing else."
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && toset(s.Resource) == toset(["arn:aws:s3:::secure-bucket-test", "arn:aws:s3:::secure-bucket-test/*"])
    ])
    error_message = "Baseline statements must deny on the bucket and every object in it."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == "1.2"
    error_message = "The TLS statement should reject versions below 1.2."
  }
}

run "versions_objects_and_cleans_up_abandoned_uploads" {
  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Versioning should be enabled by default."
  }
  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.id] == ["abort-incomplete-multipart-uploads"]
    error_message = "Only the multipart-cleanup lifecycle rule should exist by default."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Incomplete multipart uploads should be aborted after 7 days by default."
  }
}

run "is_safe_to_destroy_by_accident" {
  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false so a destroy can't silently delete data."
  }
  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging is opt-in."
  }
}
