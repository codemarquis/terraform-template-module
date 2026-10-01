terraform {
  # 1.7+ for `terraform test` mock providers; the module itself uses nothing newer than 1.5.
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}
