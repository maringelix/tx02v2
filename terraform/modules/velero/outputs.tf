output "container_id" {
  description = "Resource ID of the private Velero Blob container (the only scope of its data role)."
  value       = azurerm_storage_container.backups.id
}

output "storage_account_name" {
  description = "Storage account name used by platform/install.sh."
  value       = azurerm_storage_account.this.name
}

output "storage_account_uri" {
  description = "Blob endpoint passed to the Azure plugin, avoiding Storage Account Reader."
  value       = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
}

output "identity_client_id" {
  description = "Client ID injected into Velero's Workload Identity service account."
  value       = azurerm_user_assigned_identity.velero.client_id
}

output "identity_principal_id" {
  description = "Principal ID for the container-scoped Storage Blob Data Contributor assignment."
  value       = azurerm_user_assigned_identity.velero.principal_id
}

output "identity_id" {
  description = "Resource ID used by Velero's federated identity credential."
  value       = azurerm_user_assigned_identity.velero.id
}

output "identity_name" {
  description = "Name of the Velero user-assigned identity."
  value       = azurerm_user_assigned_identity.velero.name
}

output "identity_tags" {
  description = "Tags applied to the Velero user-assigned identity."
  value       = azurerm_user_assigned_identity.velero.tags
}

output "federated_subject" {
  description = "Only the Velero ServiceAccount may exchange its AKS token for this identity."
  value       = azurerm_federated_identity_credential.velero.subject
}

output "federated_identity_id" {
  description = "User-assigned identity trusted by the Velero federated credential."
  value       = azurerm_federated_identity_credential.velero.user_assigned_identity_id
}

output "federated_issuer" {
  description = "AKS OIDC issuer trusted by the Velero federated credential."
  value       = azurerm_federated_identity_credential.velero.issuer
}

output "federated_audiences" {
  description = "Audiences trusted by the Velero federated credential."
  value       = azurerm_federated_identity_credential.velero.audience
}

output "storage_security" {
  description = "Security settings of the private, keyless Blob container and its expiry policy."
  value = {
    public_network_access     = azurerm_storage_account.this.public_network_access
    shared_access_key_enabled = azurerm_storage_account.this.shared_access_key_enabled
    anonymous_access          = azurerm_storage_account.this.allow_nested_items_to_be_public
    container_access_type     = azurerm_storage_container.backups.container_access_type
    backup_expiration_days    = azurerm_storage_management_policy.this.rule[0].actions[0].base_blob[0].delete_after_days_since_modification_greater_than
  }
}
