output "id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "uri" {
  description = "Key Vault URI (contract key keyvault/uri)."
  value       = azurerm_key_vault.this.vault_uri
}

output "db_secret_name" {
  description = "Name of the database secret (contract: tx02v2-lab-db-app)."
  value       = azurerm_key_vault_secret.db.name
}

output "admin_token_secret_name" {
  description = "Name of the admin token secret (contract: tx02v2-lab-app-admin-token)."
  value       = azurerm_key_vault_secret.admin_token.name
}
