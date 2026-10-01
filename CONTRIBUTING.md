# Contributing

## Setup

You need Terraform 1.7+, [tflint](https://github.com/terraform-linters/tflint), [terraform-docs](https://terraform-docs.io) and, optionally, [pre-commit](https://pre-commit.com).

```bash
pre-commit install   # runs fmt, validate, tflint and terraform-docs on every commit
```

## Making a change

1. Change the module (`main.tf`, `variables.tf`, `outputs.tf`).
2. Add or update a run in `tests/` that would fail without your change. Tests use a mocked AWS provider, so `terraform test` needs no credentials.
3. If you add an input or output, run `terraform-docs .` to refresh the README tables.
4. Add an entry under **Unreleased** in `CHANGELOG.md`.
5. Open a pull request. CI must pass: fmt, validate, tests on the oldest and newest Terraform, tflint, Trivy, Checkov and the docs check.

## Security exceptions

If a scanner finding is a deliberate design choice, suppress it inline next to the resource with the reason, for example:

```hcl
#checkov:skip=CKV_AWS_144:Cross-region replication is a cost/DR decision for the caller
```

Exceptions without a reason won't be merged.

## Releasing

Pick the next version by [Semantic Versioning](https://semver.org): breaking changes to inputs or outputs need a major bump. Move the changelog entries under the new version, then:

```bash
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0   # the release workflow publishes the GitHub release
```
