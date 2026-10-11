output "server_id" {
  description = "Flexible Server resource ID."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "server_name" {
  description = "Flexible Server name."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "Private FQDN of the server (resolved through the private DNS zone)."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  description = "PostgreSQL port."
  value       = 5432
}

output "database_name" {
  description = "Database of the app."
  value       = azurerm_postgresql_flexible_server_database.app.name
}

output "administrator_login" {
  description = "Admin user name."
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}
