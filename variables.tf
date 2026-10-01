variable "bucket_name" {
  description = "Globally unique bucket name (3-63 characters: lowercase letters, numbers, hyphens and dots)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 lowercase letters, numbers, hyphens or dots, starting and ending with a letter or number."
  }

  validation {
    condition     = !can(regex("\\.\\.", var.bucket_name))
    error_message = "bucket_name must not contain two dots in a row."
  }

  validation {
    condition     = !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.bucket_name))
    error_message = "bucket_name must not look like an IP address."
  }

  validation {
    condition     = !startswith(var.bucket_name, "xn--") && !endswith(var.bucket_name, "-s3alias")
    error_message = "bucket_name must not start with \"xn--\" or end with \"-s3alias\" (reserved by S3)."
  }
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete a bucket that still contains objects. Keep false for anything that matters."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Keep every version of every object, so overwrites and deletes can be undone."
  type        = bool
  default     = true
}

# ---- Encryption ----------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of an existing KMS key for SSE-KMS. When null, the module creates a dedicated key (see create_kms_key)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:\\d{12}:(key|alias)/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key or alias ARN."
  }
}

variable "create_kms_key" {
  description = "Create a dedicated customer-managed KMS key (with rotation) when kms_key_arn is null. If false and no key is given, objects use SSE-S3 (AES-256) instead."
  type        = bool
  default     = true
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period before a created KMS key is deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}

# ---- Access ----------------------------------------------------------------------

variable "additional_policy_json" {
  description = "Extra bucket policy (for example from aws_iam_policy_document). Its statements are appended to the module's TLS-only baseline, which can't be removed."
  type        = string
  default     = null

  validation {
    condition     = var.additional_policy_json == null || can(tolist(jsondecode(var.additional_policy_json).Statement))
    error_message = "additional_policy_json must be a JSON policy document with a Statement list."
  }
}

variable "access_logging" {
  description = "Send server access logs to another bucket. That bucket must allow the logging.s3.amazonaws.com service principal and use SSE-S3."
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  default = null
}

# ---- Lifecycle ---------------------------------------------------------------------

variable "lifecycle_rules" {
  description = "Lifecycle rules. A rule that aborts incomplete multipart uploads after `abort_incomplete_multipart_upload_days` is always added."
  type = list(object({
    id                                 = string
    enabled                            = optional(bool, true)
    prefix                             = optional(string, "")
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for t in rule.transitions : contains(
          ["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"],
          t.storage_class,
        )
      ]
    ]))
    error_message = "transitions[*].storage_class must be one of STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER or DEEP_ARCHIVE."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : alltrue(concat(
        [for d in [rule.expiration_days, rule.noncurrent_version_expiration_days] : d == null || try(d >= 1, false)],
        [for t in rule.transitions : t.days >= 0],
      ))
    ])
    error_message = "Lifecycle day counts must be positive (transitions may use 0)."
  }

  validation {
    condition     = length(var.lifecycle_rules) == length(distinct([for r in var.lifecycle_rules : r.id]))
    error_message = "Lifecycle rule ids must be unique."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Delete the parts of multipart uploads that never completed after this many days (they're billed but invisible)."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}

variable "tags" {
  description = "Tags for every resource the module creates."
  type        = map(string)
  default     = {}
}
