# Bootstrap: applied once, locally, by a human who is Owner of a dedicated subscription
# (docs/RUNBOOK.md). Creates what the CI cannot create for itself: resource provider
# registrations, the state storage account, the tx02v2-lab resource group (so the CI roles can be
# scoped to it before the lab exists), the three GitHub OIDC identities with their roles and the
# subscription budget.

data "azurerm_client_config" "current" {}

locals {
  project     = "tx02v2"
  environment = "lab"
  lab_name    = "${local.project}-${local.environment}"

  tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "${var.github_owner}/${local.project}"
    # Lets scripts/leftovers.sh tell bootstrap resources (kept between rounds) from lab ones.
    Stack = "bootstrap"
  }

  # Contract: deterministic suffix for globally unique names (no random).
  suffix = substr(sha1(var.subscription_id), 0, 8)

  state_storage_account_name = "${local.project}tfstate${local.suffix}"
  state_container_name       = "tfstate"
  appconfig_endpoint         = "https://${local.lab_name}-${local.suffix}.azconfig.io"

  # Resource providers of the lab (verified 2026-10-11). Microsoft.NetworkFunction and
  # Microsoft.ServiceNetworking are required by Application Gateway for Containers;
  # Microsoft.Consumption by the budget; Microsoft.OperationalInsights and Microsoft.Insights by the
  # traces of the app (Application Insights) and the optional AKS control plane logs.
  resource_providers = [
    "Microsoft.AppConfiguration",
    "Microsoft.Compute",
    "Microsoft.Consumption",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.NetworkFunction",
    "Microsoft.OperationalInsights",
    "Microsoft.ServiceNetworking",
    "Microsoft.Storage",
  ]
}

module "roles" {
  source = "../modules/role-ids"
}

resource "azurerm_resource_group" "bootstrap" {
  name     = "${local.project}-bootstrap"
  location = var.location
  tags     = local.tags
}

# Empty until terraform/envs/lab fills it; kept between lab rounds (and by the destroy).
resource "azurerm_resource_group" "lab" {
  name     = local.lab_name
  location = var.location
  tags     = local.tags
}
