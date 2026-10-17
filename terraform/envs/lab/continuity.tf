# Opt-in DR pilot light. Resources remain in the lab resource group so the narrowly scoped apply
# identity can manage both regions. Promotion is a separate, human-approved operation; Terraform
# does not automatically promote a replica when a region is unreachable.
resource "azurerm_management_lock" "postgres" {
  count      = var.postgres_delete_lock ? 1 : 0
  name       = "${local.name}-postgres-protection"
  scope      = module.postgres.server_id
  lock_level = "CanNotDelete"
  notes      = "Educational continuity protection. Review backups and explicitly approve lock removal before teardown."
}

module "network_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/network"

  name                  = "${local.name}-dr"
  location              = var.dr_location
  resource_group_name   = data.azurerm_resource_group.lab.name
  vnet_cidr             = var.dr_vnet_cidr
  aks_nodes_subnet_cidr = var.dr_aks_nodes_subnet_cidr
  agc_subnet_cidr       = var.dr_agc_subnet_cidr
  postgres_subnet_cidr  = var.dr_postgres_subnet_cidr
  postgres_peer_cidr    = var.postgres_subnet_cidr
  tags                  = local.tags
}

# Azure documents bidirectional network and DNS reachability for privately networked PostgreSQL
# replicas across regions. Peer only the two lab VNets; no gateway transit or forwarded traffic.
resource "azurerm_virtual_network_peering" "primary_to_dr" {
  count                     = var.postgres_profile == "dr" ? 1 : 0
  name                      = "${local.name}-to-dr"
  resource_group_name       = data.azurerm_resource_group.lab.name
  virtual_network_name      = module.network.vnet_name
  remote_virtual_network_id = module.network_dr[0].vnet_id
}

resource "azurerm_virtual_network_peering" "dr_to_primary" {
  count                     = var.postgres_profile == "dr" ? 1 : 0
  name                      = "${local.name}-dr-to-primary"
  resource_group_name       = data.azurerm_resource_group.lab.name
  virtual_network_name      = module.network_dr[0].vnet_name
  remote_virtual_network_id = module.network.vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "primary_sql_from_dr" {
  count                = var.postgres_profile == "dr" ? 1 : 0
  name                 = "${local.name}-dr-vnet"
  private_dns_zone_id  = module.network.postgres_private_dns_zone_id
  virtual_network_id   = module.network_dr[0].vnet_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dr_sql_from_primary" {
  count                = var.postgres_profile == "dr" ? 1 : 0
  name                 = "${local.name}-vnet"
  private_dns_zone_id  = module.network_dr[0].postgres_private_dns_zone_id
  virtual_network_id   = module.network.vnet_id
  registration_enabled = false
  tags                 = local.tags
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # disposable DR lab; teardown is mandatory (docs/CONTINUIDADE.md)
resource "azurerm_postgresql_flexible_server" "replica" {
  count                         = var.postgres_profile == "dr" ? 1 : 0
  name                          = "${local.postgres_name_prefix}-dr-postgres"
  location                      = var.dr_location
  resource_group_name           = data.azurerm_resource_group.lab.name
  create_mode                   = "Replica"
  source_server_id              = module.postgres.server_id
  version                       = "17"
  sku_name                      = var.postgres_ha_sku
  storage_mb                    = 32768
  storage_tier                  = "P4"
  auto_grow_enabled             = false
  backup_retention_days         = var.postgres_backup_retention_days
  delegated_subnet_id           = module.network_dr[0].postgres_subnet_id
  private_dns_zone_id           = module.network_dr[0].postgres_private_dns_zone_id
  public_network_access_enabled = false
  tags                          = local.tags

  depends_on = [
    azurerm_virtual_network_peering.primary_to_dr,
    azurerm_virtual_network_peering.dr_to_primary,
    azurerm_private_dns_zone_virtual_network_link.primary_sql_from_dr,
    azurerm_private_dns_zone_virtual_network_link.dr_sql_from_primary,
  ]

  lifecycle {
    ignore_changes = [zone]
  }
}

module "aks_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/aks"

  name                      = "${local.name}-dr"
  location                  = var.dr_location
  resource_group_name       = data.azurerm_resource_group.lab.name
  node_resource_group       = "${local.name}-dr-nodes"
  kubernetes_version        = var.kubernetes_version
  tenant_id                 = local.tenant_id
  control_plane_identity_id = azurerm_user_assigned_identity.aks.id
  subnet_id                 = module.network_dr[0].aks_nodes_subnet_id
  kubelet_identity = {
    id        = azurerm_user_assigned_identity.kubelet.id
    client_id = azurerm_user_assigned_identity.kubelet.client_id
    object_id = azurerm_user_assigned_identity.kubelet.principal_id
  }
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  pod_cidr                        = var.dr_pod_cidr
  service_cidr                    = var.dr_service_cidr
  dns_service_ip                  = var.dr_dns_service_ip
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

  depends_on = [azurerm_role_assignment.pre_cluster_dr]
}

module "acr_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/acr"

  name                = "${local.acr_name}dr"
  location            = var.dr_location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

locals {
  dr_db_secret_value = var.postgres_profile == "dr" ? jsonencode({
    username = module.postgres.administrator_login
    password = ephemeral.random_password.db.result
    host     = azurerm_postgresql_flexible_server.replica[0].fqdn
    port     = "5432"
    dbname   = module.postgres.database_name
  }) : ""
}

module "keyvault_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/keyvault"

  name                = "${local.keyvault_name}-dr"
  name_prefix         = "${local.name}-dr"
  location            = var.dr_location
  resource_group_name = data.azurerm_resource_group.lab.name
  tenant_id           = local.tenant_id
  db_secret_value     = local.dr_db_secret_value
  db_secret_version   = var.db_password_version
  admin_token         = ephemeral.random_password.admin_token.result
  admin_token_version = var.admin_token_version
  tags                = local.tags
}

module "agc_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/agc"

  name                = "${local.name}-dr"
  location            = var.dr_location
  resource_group_name = data.azurerm_resource_group.lab.name
  subnet_id           = module.network_dr[0].agc_subnet_id
  enable_waf          = var.enable_waf
  tags                = local.tags
}

module "appconfig_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/appconfig"

  name                = "${local.appconfig_name}-dr"
  location            = var.dr_location
  resource_group_name = data.azurerm_resource_group.lab.name
  key_prefix          = "${local.project}/${local.environment}/"
  keys                = local.contract_keys_dr
  tags                = local.tags
}

locals {
  contract_keys_dr = var.postgres_profile == "dr" ? merge(local.contract_keys, {
    "location"                    = var.dr_location
    "cluster-name"                = module.aks_dr[0].cluster_name
    "vnet-cidr"                   = module.network_dr[0].vnet_cidr
    "agc-subnet-cidr"             = module.network_dr[0].agc_subnet_cidr
    "postgres-subnet-cidr"        = module.network_dr[0].postgres_subnet_cidr
    "acr/login-server"            = module.acr_dr[0].login_server
    "keyvault/uri"                = module.keyvault_dr[0].uri
    "db/secret-name"              = module.keyvault_dr[0].db_secret_name
    "app/admin-token-secret-name" = module.keyvault_dr[0].admin_token_secret_name
    "agc/id"                      = module.agc_dr[0].id
    "agc/frontend-name"           = module.agc_dr[0].frontend_name
    "dns/hostname"                = "disabled"
    "dns/acme-email"              = "disabled"
    "waf/policy-id"               = module.agc_dr[0].waf_policy_id
  }) : {}
}

module "velero_dr" {
  count  = var.postgres_profile == "dr" ? 1 : 0
  source = "../../modules/velero"

  name                 = "${local.name}-dr"
  storage_account_name = "tx02v2${local.suffix}drvelero"
  container_name       = "tx02v2-lab-dr-velero"
  location             = var.dr_location
  resource_group_name  = data.azurerm_resource_group.lab.name
  aks_nodes_subnet_id  = module.network_dr[0].aks_nodes_subnet_id
  oidc_issuer_url      = module.aks_dr[0].oidc_issuer_url
  tags                 = local.tags
}
