terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # storage_account_name comes from -backend-config (backend.hcl, see backend.hcl.example).
  # Entra ID authentication to the blob data plane (the state account has shared keys disabled);
  # state locking uses blob leases.
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "lab/terraform.tfstate"
    use_azuread_auth = true
  }
}
