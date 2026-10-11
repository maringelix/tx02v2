terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
  }

  # Local state on purpose: this root creates the state storage account itself. Keep
  # terraform.tfstate (git-ignored) safe, or migrate it into the container afterwards
  # (docs/RUNBOOK.md).
}
