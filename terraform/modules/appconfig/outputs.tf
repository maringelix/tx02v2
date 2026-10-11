output "id" {
  description = "App Configuration store resource ID."
  value       = azurerm_app_configuration.this.id
}

output "name" {
  description = "Store name."
  value       = azurerm_app_configuration.this.name
}

output "endpoint" {
  description = "Store endpoint (dx02v2 GitHub variable AZURE_APPCONFIG_ENDPOINT)."
  value       = azurerm_app_configuration.this.endpoint
}

output "key_names" {
  description = "Every contract key written to the store."
  value       = sort([for k in azurerm_app_configuration_key.contract : k.key])
}
