# Key Vault of the lab (contract: tx02v2-lab-<suffix>) with Azure RBAC authorization and the two
# app secrets. Secret values arrive as ephemeral values and are written only through the
# write-only argument value_wo: they never reach the plan or state. The identity that applies
# the lab needs Key Vault Secrets Officer on the vault (granted by terraform/bootstrap).
#
# Soft delete cannot be disabled (7 days here, the minimum); purge protection stays off so a
# deleted vault can be purged and its name reused. Purging needs a subscription-level permission
# the CI identities do not have: docs/ARQUITETURA.md ("A armadilha do soft delete").

# tflint-ignore: azurerm_resources_missing_prevent_destroy # lab data is disposable: every round ends with terraform destroy (docs/ARQUITETURA.md)
resource "azurerm_key_vault" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Public endpoint on purpose: GitHub-hosted runners (Terraform writes the secrets) and External
  # Secrets in AKS (egress through the AKS load balancer IP) reach it. Every data-plane request
  # still needs an Entra ID token and an RBAC role on the vault (docs/ARQUITETURA.md).
  public_network_access_enabled = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# Contract: JSON with string values username, password, host, port, dbname.
# tflint-ignore: azurerm_resources_missing_prevent_destroy # lab data is disposable: every round ends with terraform destroy (docs/ARQUITETURA.md)
resource "azurerm_key_vault_secret" "db" {
  name             = "${var.name_prefix}-db-app"
  key_vault_id     = azurerm_key_vault.this.id
  content_type     = "application/json"
  value_wo         = var.db_secret_value
  value_wo_version = var.db_secret_version
  tags             = var.tags
}

# Contract: plain string, 48 random alphanumeric characters.
# tflint-ignore: azurerm_resources_missing_prevent_destroy # lab data is disposable: every round ends with terraform destroy (docs/ARQUITETURA.md)
resource "azurerm_key_vault_secret" "admin_token" {
  name             = "${var.name_prefix}-app-admin-token"
  key_vault_id     = azurerm_key_vault.this.id
  content_type     = "text/plain"
  value_wo         = var.admin_token
  value_wo_version = var.admin_token_version
  tags             = var.tags
}
