# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-01

### Added

- Secure-by-default S3 bucket module:
  - SSE-KMS with a dedicated, rotating customer-managed key, or bring your own key, or SSE-S3
  - all public access blocked and ACLs disabled
  - a bucket policy that denies plain HTTP and TLS older than 1.2, with caller statements appended
  - versioning
  - a lifecycle rule that aborts incomplete multipart uploads, plus caller rules
  - optional server access logging
- Input validation for bucket names, KMS ARNs, policy JSON, storage classes, rule ids and day counts.
- `terraform test` suite (20 runs) using a mocked AWS provider.
- Examples: `basic` and `complete` (data bucket and access-log bucket).
- CI: fmt, validate, tests on Terraform 1.7.5 and latest, tflint, Trivy, Checkov, and a docs freshness check. Plus a tag-driven release workflow and Dependabot.

[1.0.0]: https://github.com/codemarquis/terraform-template-module/releases/tag/v1.0.0
