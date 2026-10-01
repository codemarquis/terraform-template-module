# Bad input is rejected at plan time with a clear message, before AWS is called.

mock_provider "aws" {}

variables {
  bucket_name = "secure-bucket-test"
}

run "rejects_invalid_bucket_names" {
  command = plan
  variables {
    bucket_name = "Not_A_Valid_Bucket"
  }
  expect_failures = [var.bucket_name]
}

run "rejects_bucket_names_that_look_like_ip_addresses" {
  command = plan
  variables {
    bucket_name = "192.168.10.1"
  }
  expect_failures = [var.bucket_name]
}

run "rejects_consecutive_dots" {
  command = plan
  variables {
    bucket_name = "my..bucket"
  }
  expect_failures = [var.bucket_name]
}

run "rejects_a_kms_key_that_is_not_an_arn" {
  command = plan
  variables {
    kms_key_arn = "my-key"
  }
  expect_failures = [var.kms_key_arn]
}

run "rejects_a_too_short_key_deletion_window" {
  command = plan
  variables {
    kms_key_deletion_window_in_days = 3
  }
  expect_failures = [var.kms_key_deletion_window_in_days]
}

run "rejects_policy_json_without_statements" {
  command = plan
  variables {
    additional_policy_json = "{\"Version\": \"2012-10-17\"}"
  }
  expect_failures = [var.additional_policy_json]
}

run "rejects_unknown_storage_classes" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "bad", transitions = [{ days = 30, storage_class = "COLD" }] }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_duplicate_rule_ids" {
  command = plan
  variables {
    lifecycle_rules = [
      { id = "same", expiration_days = 30 },
      { id = "same", expiration_days = 60 },
    ]
  }
  expect_failures = [var.lifecycle_rules]
}

run "rejects_zero_day_expiration" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "now", expiration_days = 0 }]
  }
  expect_failures = [var.lifecycle_rules]
}
