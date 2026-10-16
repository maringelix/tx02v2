# Blob storage for Velero. The storage account has no shared-key or anonymous access; its public
# endpoint accepts network traffic only from the AKS node subnet through the Microsoft.Storage
# service endpoint. The Azure plugin receives a workload identity and the data role is assigned by
# the lab root at container scope only (roles.tf), not at the account or resource-group scope.
# tflint-ignore: azurerm_resources_missing_prevent_destroy # statement: backup data expires after 35 days and is intentionally removed by the lab's terraform destroy (R4.8); expired_at: 2027-04-16
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access           = "Enabled"

  network_rules {
    default_action             = "Deny"
    bypass                     = []
    virtual_network_subnet_ids = [var.aks_nodes_subnet_id]
  }

  tags = var.tags
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # statement: backup data expires after 35 days and is intentionally removed by the lab's terraform destroy (R4.8); expired_at: 2027-04-16
resource "azurerm_storage_container" "backups" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "expire-velero-backups-after-35-days"
    enabled = true
    filters {
      prefix_match = ["${var.container_name}/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 35
      }
    }
  }
}

resource "azurerm_user_assigned_identity" "velero" {
  name                = "${var.name}-velero"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "velero" {
  name                      = "velero"
  user_assigned_identity_id = azurerm_user_assigned_identity.velero.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:velero:velero"
  audience                  = ["api://AzureADTokenExchange"]
}
