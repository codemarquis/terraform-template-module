# Encryption choices: bring your own KMS key, or fall back to SSE-S3.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  bucket_name = "secure-bucket-test"
}

run "uses_a_supplied_kms_key_without_creating_one" {
  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && length(aws_kms_alias.this) == 0
    error_message = "No key should be created when one is supplied."
  }
  assert {
    condition = one([
      for r in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      r.apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
    ])
    error_message = "The supplied key should encrypt the bucket."
  }
  assert {
    condition     = output.kms_key_arn == var.kms_key_arn && output.encryption == "aws:kms"
    error_message = "Outputs should report the supplied key."
  }
}

run "falls_back_to_sse_s3_when_kms_is_turned_off" {
  variables {
    create_kms_key = false
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      r.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" && !r.bucket_key_enabled
    ])
    error_message = "Without a KMS key, objects should still be encrypted with SSE-S3."
  }
  assert {
    condition     = output.kms_key_arn == null && output.encryption == "AES256"
    error_message = "Outputs should report SSE-S3."
  }
}
