# Lab root: composes the modules for tx02v2-lab inside the resource group created by
# terraform/bootstrap. Names, tags and published values follow docs/CONTRATO.md (the contract with
# dx02v2). Nothing here talks to the Kubernetes API: controllers and manifests are installed by
# platform/install.sh. Every role assignment of the lab lives in roles.tf.

data "azurerm_client_config" "current" {}

# Created by terraform/bootstrap, so the CI identities can be scoped to it before the lab exists.
data "azurerm_resource_group" "lab" {
  name = local.name
}

locals {
  project     = "tx02v2"
  environment = "lab"
  name        = "${local.project}-${local.environment}"

  # Contract tags on every taggable resource (azurerm has no provider default tags; the harness
  # check policy-tags enforces `tags` on every resource type whose schema has it).
  tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "${var.github_owner}/${local.project}"
  }

  subscription_id = data.azurerm_client_config.current.subscription_id
  tenant_id       = data.azurerm_client_config.current.tenant_id

  # Contract: deterministic suffix for globally unique names (no random).
  suffix = substr(sha1(local.subscription_id), 0, 8)

  keyvault_name       = "${local.name}-${local.suffix}"
  appconfig_name      = "${local.name}-${local.suffix}"
  acr_name            = "${replace(local.name, "-", "")}${local.suffix}"
  node_resource_group = "${local.name}-nodes"

  # The PostgreSQL server name is a global DNS name (<name>.postgres.database.azure.com): without the
  # suffix, the lab of one fork would block the apply of every other one. The module appends -postgres.
  postgres_name_prefix = "${local.name}-${local.suffix}"
}

check "location_matches_resource_group" {
  assert {
    condition     = data.azurerm_resource_group.lab.location == var.location
    error_message = "var.location (${var.location}) differs from the location of the ${local.name} resource group (${data.azurerm_resource_group.lab.location}); use the location given to terraform/bootstrap."
  }
}

module "roles" {
  source = "../../modules/role-ids"
}

module "network" {
  source                   = "../../modules/network"
  storage_service_endpoint = var.postgres_profile == "dr" ? "Microsoft.Storage.Global" : "Microsoft.Storage"

  name                  = local.name
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.lab.name
  vnet_cidr             = var.vnet_cidr
  aks_nodes_subnet_cidr = var.aks_nodes_subnet_cidr
  agc_subnet_cidr       = var.agc_subnet_cidr
  postgres_subnet_cidr  = var.postgres_subnet_cidr
  postgres_peer_cidr    = var.postgres_profile == "dr" ? var.dr_postgres_subnet_cidr : ""
  tags                  = local.tags
}

module "aks" {
  source = "../../modules/aks"

  name                      = local.name
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.lab.name
  node_resource_group       = local.node_resource_group
  kubernetes_version        = var.kubernetes_version
  tenant_id                 = local.tenant_id
  control_plane_identity_id = azurerm_user_assigned_identity.aks.id
  subnet_id                 = module.network.aks_nodes_subnet_id

  kubelet_identity = {
    id        = azurerm_user_assigned_identity.kubelet.id
    client_id = azurerm_user_assigned_identity.kubelet.client_id
    object_id = azurerm_user_assigned_identity.kubelet.principal_id
  }
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  pod_cidr                        = var.pod_cidr
  service_cidr                    = var.service_cidr
  dns_service_ip                  = var.dns_service_ip
  enable_spot_pool                = var.enable_spot_pool
  spot_max_price                  = var.spot_max_price
  node_vm_size                    = var.node_vm_size
  node_os_disk_type               = var.node_os_disk_type
  node_os_disk_size_gb            = var.node_os_disk_size_gb
  node_max_pods                   = var.node_max_pods
  node_count                      = var.node_count
  node_min_count                  = var.node_min_count
  node_max_count                  = var.node_max_count
  enable_control_plane_logs       = var.enable_control_plane_logs
  log_retention_days              = var.log_retention_days
  log_daily_quota_gb              = var.log_daily_quota_gb
  tags                            = local.tags

  # The control plane identity must be able to join the node subnet and assign the kubelet
  # identity before AKS creates the cluster.
  depends_on = [azurerm_role_assignment.pre_cluster]
}

module "postgres" {
  source = "../../modules/postgres"

  name                         = local.postgres_name_prefix
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.lab.name
  delegated_subnet_id          = module.network.postgres_subnet_id
  private_dns_zone_id          = module.network.postgres_private_dns_zone_id
  backup_retention_days        = var.postgres_backup_retention_days
  sku_name                     = var.postgres_profile == "core" ? "B_Standard_B1ms" : var.postgres_ha_sku
  continuity_profile           = var.postgres_profile
  geo_redundant_backup_enabled = var.postgres_profile == "dr" || var.postgres_geo_backup
  administrator_password       = ephemeral.random_password.db.result
  password_version             = var.db_password_version
  tags                         = local.tags

  # The private DNS zone must be linked to the VNet and the subnet NSG attached first.
  depends_on = [module.network]
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = local.keyvault_name
  name_prefix         = local.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tenant_id           = local.tenant_id
  db_secret_value     = local.db_secret_value
  db_secret_version   = var.db_password_version
  admin_token         = ephemeral.random_password.admin_token.result
  admin_token_version = var.admin_token_version
  tags                = local.tags
}

module "acr" {
  source = "../../modules/acr"

  name                = local.acr_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

module "agc" {
  source = "../../modules/agc"

  name                = local.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  subnet_id           = module.network.agc_subnet_id
  enable_waf          = var.enable_waf
  tags                = local.tags
}

module "appconfig" {
  source = "../../modules/appconfig"

  name                = local.appconfig_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  key_prefix          = "${local.project}/${local.environment}/"
  keys                = local.contract_keys
  tags                = local.tags
}

module "velero" {
  source              = "../../modules/velero"
  replication_type    = var.postgres_profile == "dr" ? "RAGRS" : "LRS"
  recovery_subnet_ids = var.postgres_profile == "dr" ? [module.network_dr[0].aks_nodes_subnet_id] : []

  name                 = local.name
  storage_account_name = "${replace(local.name, "-", "")}${local.suffix}velero"
  container_name       = "tx02v2-lab-velero"
  location             = var.location
  resource_group_name  = data.azurerm_resource_group.lab.name
  aks_nodes_subnet_id  = module.network.aks_nodes_subnet_id
  oidc_issuer_url      = module.aks.oidc_issuer_url
  tags                 = local.tags
}
