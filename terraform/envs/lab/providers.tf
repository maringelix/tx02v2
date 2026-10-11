# Credentials come from the environment: OIDC in the workflows (ARM_USE_OIDC, ARM_CLIENT_ID,
# ARM_TENANT_ID, ARM_SUBSCRIPTION_ID) or the Azure CLI locally (ARM_SUBSCRIPTION_ID required).
provider "azurerm" {
  # The CI identities cannot register resource providers (nothing at subscription scope):
  # terraform/bootstrap registers the ones the lab needs.
  resource_provider_registrations = "none"
  storage_use_azuread             = true

  features {
    key_vault {
      # Purging a soft-deleted vault needs Microsoft.KeyVault/locations/deletedVaults/purge/action
      # at subscription scope: true only when the identity running destroy has it (for example the
      # subscription Owner destroying locally). The CI apply identity does not (docs/ARQUITETURA.md).
      purge_soft_delete_on_destroy = var.purge_key_vault_on_destroy
      # A fresh vault every round: never silently recover a soft-deleted one with stale contents.
      recover_soft_deleted_key_vaults = false
      # Secret purge/recover are data actions of Key Vault Secrets Officer on the vault.
      purge_soft_deleted_secrets_on_destroy = true
      recover_soft_deleted_secrets          = true
    }

    app_configuration {
      # With recover_soft_deleted = true the provider reads deletedConfigurationStores at
      # subscription scope and fails on 403 (verified in the azurerm 5.9.0 source). The Free tier
      # has no soft delete, so neither purge nor recovery is needed.
      purge_soft_delete_on_destroy = false
      recover_soft_deleted         = false
    }

    log_analytics_workspace {
      # Lets the next round reuse the workspace name (only when enable_control_plane_logs = true).
      permanently_delete_on_destroy = true
    }
  }
}
