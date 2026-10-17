# modules/postgres, modules/keyvault, modules/acr and modules/appconfig tested directly. The
# PostgreSQL and Key Vault runs prove that no secret lands in plan or state: only write-only
# arguments and their versions are set (write-only attributes are always null).

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner        = "maringelix"
  name                = "tx02v2-lab"
  location            = "eastus2"
  resource_group_name = "tx02v2-lab"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/postgres"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/privateDnsZones/tx02v2-lab.private.postgres.database.azure.com"
  tags                = { Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" }

  # Test-only placeholders for the ephemeral inputs (never real values).
  administrator_password = "placeholder-not-a-secret"
  password_version       = 1
  db_secret_value        = "{}"
  db_secret_version      = 1
  admin_token            = "placeholder-not-a-token"
  admin_token_version    = 1
}

run "postgres_server" {
  command = apply

  module {
    source = "../../modules/postgres"
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server.this.name == "tx02v2-lab-postgres" &&
      azurerm_postgresql_flexible_server.this.version == "17" &&
      azurerm_postgresql_flexible_server.this.sku_name == "B_Standard_B1ms" &&
      azurerm_postgresql_flexible_server.this.storage_mb == 32768 &&
      azurerm_postgresql_flexible_server.this.storage_tier == "P4" &&
      azurerm_postgresql_flexible_server.this.auto_grow_enabled == false
    )
    error_message = "PostgreSQL Flexible Server 17 on B_Standard_B1ms with 32 GB (P4)."
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server.this.public_network_access_enabled == false &&
      azurerm_postgresql_flexible_server.this.delegated_subnet_id == var.delegated_subnet_id &&
      azurerm_postgresql_flexible_server.this.private_dns_zone_id == var.private_dns_zone_id
    )
    error_message = "Private access only: delegated subnet + private DNS zone, public network access disabled."
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server.this.backup_retention_days == 7 &&
      azurerm_postgresql_flexible_server.this.geo_redundant_backup_enabled == false &&
      length(azurerm_postgresql_flexible_server.this.high_availability) == 0
    )
    error_message = "Lab defaults: 7-day backups (the minimum), no geo-redundancy, no HA."
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server.this.authentication[0].password_auth_enabled &&
      azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled == false &&
      azurerm_postgresql_flexible_server.this.administrator_login == "dx02v2_admin"
    )
    error_message = "Password authentication with the dx02v2_admin user."
  }

  assert {
    condition = { for c in azurerm_postgresql_flexible_server_configuration.this : c.name => c.value } == {
      require_secure_transport   = "on"
      ssl_min_protocol_version   = "TLSv1.2"
      log_min_duration_statement = "1000"
    }
    error_message = "TLS only (1.2 or newer) and slow query logging (over 1 s)."
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server_database.app.name == "dx02v2" &&
      azurerm_postgresql_flexible_server_database.app.charset == "UTF8" &&
      azurerm_postgresql_flexible_server_database.app.server_id == azurerm_postgresql_flexible_server.this.id
    )
    error_message = "The app database dx02v2 (UTF8) must exist."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.tags == var.tags
    error_message = "The server carries the contract tags."
  }
}

run "postgres_zone_redundant_ha_and_geo_backup" {
  command = apply

  module {
    source = "../../modules/postgres"
  }

  variables {
    sku_name                     = "GP_Standard_D2ads_v5"
    continuity_profile           = "dr"
    geo_redundant_backup_enabled = true
    backup_retention_days        = 14
  }

  assert {
    condition = (
      azurerm_postgresql_flexible_server.this.sku_name == "GP_Standard_D2ads_v5" &&
      azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant" &&
      azurerm_postgresql_flexible_server.this.geo_redundant_backup_enabled == true &&
      azurerm_postgresql_flexible_server.this.backup_retention_days == 14 &&
      azurerm_postgresql_flexible_server.this.public_network_access_enabled == false
    )
    error_message = "HA/DR uses General Purpose, zone-redundant standby, geo backup and private access."
  }
}

run "postgres_password_never_in_plan_or_state" {
  command = apply

  module {
    source = "../../modules/postgres"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.administrator_password == null && azurerm_postgresql_flexible_server.this.administrator_password_wo == null
    error_message = "No password may be stored for the server (plaintext argument unset, write-only value never persisted)."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.administrator_password_wo_version == 1
    error_message = "The password is sent only through administrator_password_wo (version 1 by default)."
  }
}

run "postgres_password_rotation" {
  command = plan

  module {
    source = "../../modules/postgres"
  }

  variables {
    password_version = 2
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.administrator_password_wo_version == 2
    error_message = "password_version must drive administrator_password_wo_version."
  }
}

run "key_vault_and_secrets" {
  command = apply

  module {
    source = "../../modules/keyvault"
  }

  variables {
    name        = "tx02v2-lab-b602d594"
    name_prefix = "tx02v2-lab"
  }

  assert {
    condition = (
      azurerm_key_vault.this.name == "tx02v2-lab-b602d594" &&
      azurerm_key_vault.this.rbac_authorization_enabled &&
      azurerm_key_vault.this.sku_name == "standard" &&
      azurerm_key_vault.this.tenant_id == "00000000-0000-0000-0000-000000000000"
    )
    error_message = "Key Vault tx02v2-lab-<suffix> with Azure RBAC authorization (no access policies)."
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 7 && azurerm_key_vault.this.purge_protection_enabled == false
    error_message = "Soft delete 7 days (minimum) and purge protection off, so a deleted vault can be purged and its name reused."
  }

  assert {
    condition = (
      azurerm_key_vault.this.public_network_access_enabled &&
      azurerm_key_vault.this.network_acls[0].default_action == "Allow" &&
      azurerm_key_vault.this.network_acls[0].bypass == "AzureServices"
    )
    error_message = "Public endpoint on purpose (GitHub-hosted runners and AKS egress), documented in docs/ARQUITETURA.md."
  }

  assert {
    condition     = azurerm_key_vault_secret.db[0].name == "tx02v2-lab-db-app" && azurerm_key_vault_secret.admin_token[0].name == "tx02v2-lab-app-admin-token"
    error_message = "Secret names must follow the contract."
  }

  assert {
    condition = (
      azurerm_key_vault_secret.db[0].value == null && azurerm_key_vault_secret.db[0].value_wo == null &&
      azurerm_key_vault_secret.admin_token[0].value == null && azurerm_key_vault_secret.admin_token[0].value_wo == null
    )
    error_message = "Secret values must never be stored (plaintext value unset, write-only value never persisted)."
  }

  assert {
    condition = (
      azurerm_key_vault_secret.db[0].value_wo_version == 1 && azurerm_key_vault_secret.admin_token[0].value_wo_version == 1 &&
      azurerm_key_vault_secret.db[0].content_type == "application/json" && azurerm_key_vault_secret.admin_token[0].content_type == "text/plain"
    )
    error_message = "Secrets are written through value_wo (version 1) with their content types."
  }

  assert {
    condition = alltrue([
      for t in [azurerm_key_vault.this.tags, azurerm_key_vault_secret.db[0].tags, azurerm_key_vault_secret.admin_token[0].tags] : t == var.tags
    ])
    error_message = "The vault and its secrets carry the contract tags."
  }

  assert {
    condition     = output.uri == "https://tx02v2-lab-b602d594.vault.azure.net/"
    error_message = "The vault URI is the contract key keyvault/uri."
  }
}

run "secret_rotation" {
  command = plan

  module {
    source = "../../modules/keyvault"
  }

  variables {
    name                = "tx02v2-lab-b602d594"
    name_prefix         = "tx02v2-lab"
    db_secret_version   = 2
    admin_token_version = 3
  }

  assert {
    condition     = azurerm_key_vault_secret.db[0].value_wo_version == 2 && azurerm_key_vault_secret.admin_token[0].value_wo_version == 3
    error_message = "The versions must drive value_wo_version (rotation)."
  }
}

run "container_registry" {
  command = apply

  module {
    source = "../../modules/acr"
  }

  variables {
    name = "tx02v2labb602d594"
  }

  assert {
    condition = (
      azurerm_container_registry.this.name == "tx02v2labb602d594" &&
      azurerm_container_registry.this.sku == "Standard" &&
      azurerm_container_registry.this.role_assignment_mode == "AbacRepositoryPermissions" &&
      azurerm_container_registry.this.admin_enabled == false &&
      azurerm_container_registry.this.anonymous_pull_enabled == false
    )
    error_message = "ACR Standard with repository ABAC enabled, the admin user and anonymous pull disabled."
  }

  assert {
    condition     = azurerm_container_registry.this.tags == var.tags && output.login_server == "tx02v2labb602d594.azurecr.io"
    error_message = "The registry carries the contract tags; its login server is the contract key acr/login-server."
  }
}

run "contract_store" {
  command = apply

  module {
    source = "../../modules/appconfig"
  }

  variables {
    name       = "tx02v2-lab-b602d594"
    key_prefix = "tx02v2/lab/"
    keys = {
      "location" = "eastus2"
      "agc/id"   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc"
    }
  }

  assert {
    condition = (
      azurerm_app_configuration.this.sku == "free" &&
      azurerm_app_configuration.this.local_auth_enabled == false &&
      azurerm_app_configuration.this.public_network_access == "Enabled" &&
      azurerm_app_configuration.this.purge_protection_enabled == false
    )
    error_message = "Free tier store with access keys disabled (Entra ID only)."
  }

  assert {
    condition = { for k in azurerm_app_configuration_key.contract : k.key => k.value } == {
      "tx02v2/lab/location" = "eastus2"
      "tx02v2/lab/agc/id"   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc"
    }
    error_message = "Every contract key is written under the prefix tx02v2/lab/."
  }

  assert {
    condition = alltrue([
      for k in azurerm_app_configuration_key.contract :
      k.label == null && k.type == "kv" && k.configuration_store_id == azurerm_app_configuration.this.id && k.tags == var.tags
    ])
    error_message = "Keys have no label (contract), are plain key-values of this store and carry the tags."
  }

  assert {
    condition     = azurerm_app_configuration.this.tags == var.tags
    error_message = "The store carries the contract tags."
  }
}
