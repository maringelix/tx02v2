# Azure Database for PostgreSQL Flexible Server 17 for dx02v2, private access only (delegated
# subnet + private DNS zone). The admin password arrives as an ephemeral value and is sent only
# through the write-only argument administrator_password_wo: it never reaches the plan or state.

# tflint-ignore: azurerm_resources_missing_prevent_destroy # lab data is disposable: every round ends with terraform destroy (docs/ARCHITECTURE.md)
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "${var.name}-postgres"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = "17"
  sku_name            = var.sku_name
  storage_mb          = var.storage_mb
  storage_tier        = var.storage_tier
  auto_grow_enabled   = false

  # Private access: the server only gets an IP in the delegated subnet.
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  administrator_login               = var.administrator_login
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.password_version

  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = false
  }

  # Defaults stay cheap. HA/DR use a General Purpose SKU and a zone-redundant standby.
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  dynamic "high_availability" {
    for_each = var.continuity_profile == "core" ? [] : [1]
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = var.tags

  lifecycle {
    # Azure picks an availability zone when none is set; ignoring it avoids a perpetual diff
    # (the provider can only change the zone through an HA failover).
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }
}

# Server parameters: TLS only (1.2+) and slow query logging (statements over 1 s).
resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = {
    require_secure_transport   = "on"
    ssl_min_protocol_version   = "TLSv1.2"
    log_min_duration_statement = "1000"
  }

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # lab data is disposable: every round ends with terraform destroy (docs/ARCHITECTURE.md)
resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
