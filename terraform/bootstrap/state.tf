# Remote state of the lab root: one private container in a hardened StorageV2 account.
# Locking uses blob leases (azurerm backend). Shared keys are disabled, so every access needs an
# Entra ID identity with a Storage Blob Data role on the container: the subscription Owner has
# no data actions and gets Storage Blob Data Contributor below (docs/ARCHITECTURE.md).

# tflint-ignore: azurerm_resources_missing_prevent_destroy # protected by the CanNotDelete lock below, which state_protection_lock = false removes for the final teardown
resource "azurerm_storage_account" "state" {
  name                     = local.state_storage_account_name
  resource_group_name      = azurerm_resource_group.bootstrap.name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.state_replication_type
  access_tier              = "Hot"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  local_user_enabled                = false
  sftp_enabled                      = false
  infrastructure_encryption_enabled = true

  # Public endpoint: GitHub-hosted runners have no fixed IP. Requests still need Entra ID + RBAC.
  public_network_access = "Enabled"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # covered by the account lock below (a locked account cannot lose its containers through ARM)
resource "azurerm_storage_container" "state" {
  name                  = local.state_container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# The state outlives every lab round: Azure refuses to delete the locked account. Unlike
# lifecycle.prevent_destroy, a lock can be lifted by a variable for the final teardown
# (docs/RUNBOOK.md, "Teardown do bootstrap"). Container soft delete and blob versioning protect
# against deletions inside the account.
resource "azurerm_management_lock" "state" {
  count = var.state_protection_lock ? 1 : 0

  name       = "tx02v2-state-cannot-delete"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Remote state of tx02v2-lab. Set state_protection_lock = false only for the final teardown."
}

# The human running the bootstrap (to migrate this state and to read the lab state locally).
resource "azurerm_role_assignment" "state_operator" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "tx02v2 bootstrap operator: lab and bootstrap state"
}
