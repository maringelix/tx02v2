# Applied by a human who is Owner of a dedicated subscription, with the Azure CLI (az login).
provider "azurerm" {
  # Explicit on purpose: the bootstrap refuses to guess which subscription it changes.
  subscription_id = var.subscription_id

  # v1 failed with MissingSubscriptionRegistration because registration was manual. Here the
  # provider registers exactly the namespaces the lab needs (idempotent, never unregisters);
  # the CI identities could not do it (nothing at subscription scope).
  resource_provider_registrations = "none"
  resource_providers_to_register  = local.resource_providers

  # The state account has shared keys disabled: data-plane calls use Entra ID.
  storage_use_azuread = true

  features {
    resource_group {
      # Teardown stops if the lab resource group still has resources (destroy the lab first).
      prevent_deletion_if_contains_resources = true
    }

    storage {
      # The account and its container are managed through ARM only; the Owner running the
      # bootstrap has no blob data role until the container role assignment exists.
      data_plane_available = false
    }
  }
}
