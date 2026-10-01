# Optional features: lifecycle rules, access logging, extra policy statements.

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
}

variables {
  bucket_name = "secure-bucket-test"
}

run "adds_lifecycle_rules_after_the_multipart_cleanup" {
  variables {
    abort_incomplete_multipart_upload_days = 3
    lifecycle_rules = [
      {
        id                                 = "archive-logs"
        prefix                             = "logs/"
        expiration_days                    = 365
        noncurrent_version_expiration_days = 30
        transitions = [
          { days = 30, storage_class = "STANDARD_IA" },
          { days = 90, storage_class = "GLACIER_IR" },
        ]
      },
      { id = "paused", enabled = false, expiration_days = 7 },
    ]
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.id] == ["abort-incomplete-multipart-uploads", "archive-logs", "paused"]
    error_message = "Caller rules should follow the built-in multipart cleanup rule."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 3
    error_message = "The multipart cleanup window should be configurable."
  }
  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[1].filter[0].prefix == "logs/"
      && [for t in aws_s3_bucket_lifecycle_configuration.this.rule[1].transition : t.storage_class] == ["STANDARD_IA", "GLACIER_IR"]
      && aws_s3_bucket_lifecycle_configuration.this.rule[1].expiration[0].days == 365
      && aws_s3_bucket_lifecycle_configuration.this.rule[1].noncurrent_version_expiration[0].noncurrent_days == 30
    )
    error_message = "Prefix, transitions, expiration and noncurrent expiration should all be applied."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[2].status == "Disabled"
    error_message = "enabled = false should disable a rule."
  }
  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "abort-incomplete-multipart-uploads"
      && aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled"
    )
    error_message = "The multipart cleanup rule must stay first and enabled even when caller rules are added."
  }
}

run "sends_access_logs_with_a_default_prefix" {
  variables {
    access_logging = { target_bucket = "central-access-logs" }
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "central-access-logs"
    error_message = "Logs should go to the given bucket."
  }
  assert {
    condition     = aws_s3_bucket_logging.this[0].target_prefix == "secure-bucket-test/"
    error_message = "The log prefix should default to the bucket name."
  }
}

run "appends_extra_policy_statements_after_the_baseline" {
  variables {
    additional_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::secure-bucket-test/*"
      }]
    })
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTLS", "AllowCloudFrontRead"]
    error_message = "Extra statements should be added without dropping the TLS baseline."
  }
}

run "can_suspend_versioning" {
  variables {
    versioning_enabled = false
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Suspended"
    error_message = "versioning_enabled = false should suspend versioning."
  }
}
