# AKS cluster of the lab (contract: docs/CONTRATO.md). Free tier control plane, Entra ID
# authentication with Azure RBAC for Kubernetes authorization, local accounts disabled, OIDC
# issuer + workload identity, Azure CNI Overlay with the Cilium dataplane (enforces
# NetworkPolicy), one autoscaled system node pool on Azure Linux. Nothing here talks to the
# Kubernetes API: the platform layer is installed by platform/install.sh.

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  node_resource_group = var.node_resource_group

  # Patch upgrades of the minor in kubernetes_version and weekly node images, both by AKS.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Only Entra ID identities: no static admin kubeconfig exists.
  local_account_disabled            = true
  role_based_access_control_enabled = true

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Add-ons stay off (cost, and the v1 lesson of Gatekeeper fighting the Azure Policy add-on).
  azure_policy_enabled             = false
  http_application_routing_enabled = false

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  # Public API server restricted to var.api_server_authorized_ip_ranges (0.0.0.0/0 needs
  # allow_api_server_from_anywhere = true in the root). Every request still needs an Entra ID
  # token plus an Azure RBAC or Kubernetes RBAC grant (docs/ARQUITETURA.md).
  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  # User-assigned control plane identity: before the cluster exists it gets Network Contributor on
  # the node subnet and Managed Identity Operator on the kubelet identity
  # (terraform/envs/lab/roles.tf).
  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity_id]
  }

  # Pre-created kubelet identity (repository-scoped ACR Reader): known before the cluster, kept in the
  # lab resource group instead of the AKS-owned node resource group.
  kubelet_identity {
    client_id                 = var.kubelet_identity.client_id
    object_id                 = var.kubelet_identity.object_id
    user_assigned_identity_id = var.kubelet_identity.id
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    vnet_subnet_id               = var.subnet_id
    os_sku                       = "AzureLinux"
    os_disk_type                 = var.node_os_disk_type
    os_disk_size_gb              = var.node_os_disk_size_gb
    max_pods                     = var.node_max_pods
    auto_scaling_enabled         = true
    min_count                    = var.node_min_count
    max_count                    = var.node_max_count
    node_count                   = var.node_count
    only_critical_addons_enabled = false
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge                     = "1"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  # Required block since azurerm 5.0; Manual = no node auto-provisioning (the cluster autoscaler
  # of the system pool scales the lab).
  node_provisioning_profile {
    mode = "Manual"
  }

  tags = var.tags

  lifecycle {
    # The cluster autoscaler owns the node count after creation.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# --- Control plane logs (optional, off by default: Log Analytics ingestion is billed per GB) ---

resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_control_plane_logs ? 1 : 0

  name                = "${var.name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "control_plane" {
  count = var.enable_control_plane_logs ? 1 : 0

  name                           = "control-plane"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this[0].id
  log_analytics_destination_type = "Dedicated"

  # Audit without get/list/watch (much smaller than kube-audit) and Entra ID authentication.
  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }
}
