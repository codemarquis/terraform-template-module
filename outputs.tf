output "bucket_id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN, for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket domain name (bucket.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Region-specific bucket domain name, for CloudFront origins."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the bucket (created or supplied), or null for SSE-S3. Readers and writers need kms:Decrypt / kms:GenerateDataKey on it."
  value       = local.kms_key_arn
}

output "encryption" {
  description = "Server-side encryption in use: \"aws:kms\" or \"AES256\"."
  value       = local.use_kms ? "aws:kms" : "AES256"
}
