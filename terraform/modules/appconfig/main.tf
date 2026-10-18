# App Configuration store of the cross-repo contract (docs/CONTRACT.md): Free tier, access keys
# disabled (Entra ID + RBAC only), one key-value per contract key, no labels, prefix tx02v2/lab/.
# The identity that applies the lab needs App Configuration Data Owner (granted by
# terraform/bootstrap); dx02v2-gha-deploy reads with App Configuration Data Reader.
# Free tier limits (verified 2026-10-11): 3 stores per region per subscription, 10 MB,
# 1,000 requests per day, no soft delete (the name is free again right after a destroy).

resource "azurerm_app_configuration" "this" {
  name                     = var.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = "free"
  local_auth_enabled       = false
  public_network_access    = "Enabled"
  purge_protection_enabled = false
  tags                     = var.tags
}

resource "azurerm_app_configuration_key" "contract" {
  for_each = var.keys

  configuration_store_id = azurerm_app_configuration.this.id
  key                    = "${var.key_prefix}${each.key}"
  value                  = each.value
  type                   = "kv"
  tags                   = var.tags
}
