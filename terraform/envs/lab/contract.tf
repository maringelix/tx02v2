# Cross-repo contract (docs/CONTRATO.md): the values dx02v2 and platform/install.sh read from App
# Configuration (prefix tx02v2/lab/, no label). None of them is a secret.

locals {
  contract_keys = {
    "location"                    = var.location
    "resource-group"              = data.azurerm_resource_group.lab.name
    "cluster-name"                = module.aks.cluster_name
    "vnet-cidr"                   = module.network.vnet_cidr
    "agc-subnet-cidr"             = module.network.agc_subnet_cidr
    "postgres-subnet-cidr"        = module.network.postgres_subnet_cidr
    "acr/login-server"            = module.acr.login_server
    "keyvault/uri"                = module.keyvault.uri
    "db/secret-name"              = module.keyvault.db_secret_name
    "app/admin-token-secret-name" = module.keyvault.admin_token_secret_name
    "eso/cluster-secret-store"    = "azure-key-vault"
    "agc/id"                      = module.agc.id
    "agc/frontend-name"           = module.agc.frontend_name
    "dns/hostname"                = local.dns_enabled ? var.app_domain_name : "disabled"
    "dns/acme-email"              = local.dns_enabled ? var.acme_contact_email : "disabled"
    "waf/policy-id"               = module.agc.waf_policy_id
    "deploy/principal-id"         = var.deploy_principal_id
  }
}
