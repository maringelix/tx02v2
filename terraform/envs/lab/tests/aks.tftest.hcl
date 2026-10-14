# modules/aks tested directly (run blocks with a module source) so assertions can read the
# resources inside the module.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner                    = "maringelix"
  name                            = "tx02v2-lab"
  location                        = "eastus2"
  resource_group_name             = "tx02v2-lab"
  node_resource_group             = "tx02v2-lab-nodes"
  kubernetes_version              = "1.36"
  tenant_id                       = "00000000-0000-0000-0000-000000000000"
  control_plane_identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-aks"
  subnet_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/aks-nodes"
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  kubelet_identity = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-kubelet"
    client_id = "88888888-8888-8888-8888-888888888888"
    object_id = "77777777-7777-7777-7777-777777777777"
  }
  pod_cidr                  = "10.244.0.0/16"
  service_cidr              = "10.0.0.0/16"
  dns_service_ip            = "10.0.0.10"
  node_vm_size              = "Standard_D2als_v6"
  node_os_disk_type         = "Managed"
  node_os_disk_size_gb      = 30
  node_max_pods             = 110
  node_count                = 2
  node_min_count            = 1
  node_max_count            = 3
  enable_control_plane_logs = false
  log_retention_days        = 30
  log_daily_quota_gb        = 0.5
  tags                      = { Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" }
}

run "control_plane" {
  command = plan

  module {
    source = "../../modules/aks"
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.name == "tx02v2-lab" &&
      azurerm_kubernetes_cluster.this.kubernetes_version == "1.36" &&
      azurerm_kubernetes_cluster.this.sku_tier == "Free" &&
      azurerm_kubernetes_cluster.this.node_resource_group == "tx02v2-lab-nodes"
    )
    error_message = "Cluster tx02v2-lab: Kubernetes 1.36, Free tier, node resource group tx02v2-lab-nodes."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.automatic_upgrade_channel == "patch" && azurerm_kubernetes_cluster.this.node_os_upgrade_channel == "NodeImage"
    error_message = "AKS must apply Kubernetes patches and node images automatically."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.role_based_access_control_enabled
    error_message = "Local accounts must be disabled (no static admin kubeconfig) and Kubernetes RBAC on."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled &&
      azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].tenant_id == "00000000-0000-0000-0000-000000000000" &&
      length(coalesce(azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].admin_group_object_ids, [])) == 0
    )
    error_message = "Entra ID integration with Azure RBAC for Kubernetes authorization (admins get roles, not an admin group)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "The OIDC issuer and workload identity are required by ESO and the ALB Controller."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges == toset(["203.0.113.10/32"])
    error_message = "The API server must be restricted to api_server_authorized_ip_ranges."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.identity[0].type == "UserAssigned" &&
      azurerm_kubernetes_cluster.this.identity[0].identity_ids == toset([var.control_plane_identity_id])
    )
    error_message = "The control plane must use the user-assigned identity (it can join the node subnet before creation)."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.kubelet_identity[0].user_assigned_identity_id == var.kubelet_identity.id &&
      azurerm_kubernetes_cluster.this.kubelet_identity[0].client_id == var.kubelet_identity.client_id &&
      azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id == var.kubelet_identity.object_id &&
      output.kubelet_object_id == var.kubelet_identity.object_id
    )
    error_message = "The kubelets must use the pre-created kubelet identity (AcrPull)."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure" &&
      azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay" &&
      azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium" &&
      azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium"
    )
    error_message = "Azure CNI Overlay with the Cilium dataplane, which enforces NetworkPolicy (contract)."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.network_profile[0].pod_cidr == "10.244.0.0/16" &&
      azurerm_kubernetes_cluster.this.network_profile[0].service_cidr == "10.0.0.0/16" &&
      azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip == "10.0.0.10" &&
      azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "loadBalancer" &&
      azurerm_kubernetes_cluster.this.network_profile[0].load_balancer_sku == "standard"
    )
    error_message = "Pod/service CIDRs must follow the variables; egress through the standard load balancer."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.azure_policy_enabled == false &&
      azurerm_kubernetes_cluster.this.http_application_routing_enabled == false &&
      length(azurerm_kubernetes_cluster.this.oms_agent) == 0 &&
      length(azurerm_kubernetes_cluster.this.microsoft_defender) == 0 &&
      length(azurerm_kubernetes_cluster.this.ingress_application_gateway) == 0 &&
      length(azurerm_kubernetes_cluster.this.web_app_routing) == 0 &&
      length(azurerm_kubernetes_cluster.this.key_vault_secrets_provider) == 0 &&
      length(azurerm_kubernetes_cluster.this.service_mesh_profile) == 0
    )
    error_message = "Add-ons stay off (cost; Azure Policy add-on lesson of v1; ingress-nginx based routing is retired)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_provisioning_profile[0].mode == "Manual"
    error_message = "Node auto-provisioning stays off: the cluster autoscaler of the system pool scales the lab."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.tags == var.tags
    error_message = "The cluster carries the contract tags."
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 0 && length(azurerm_monitor_diagnostic_setting.control_plane) == 0
    error_message = "Control plane logs are opt-in (Log Analytics is billed per GB)."
  }
}

run "system_node_pool" {
  command = plan

  module {
    source = "../../modules/aks"
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].name == "system" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size == "Standard_D2als_v6" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].vnet_subnet_id == var.subnet_id &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].os_sku == "AzureLinux"
    )
    error_message = "The system pool runs Azure Linux on Standard_D2als_v6 in the node subnet."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == 1 &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].max_count == 3 &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].node_count == 2
    )
    error_message = "Cluster autoscaler min 1 / max 3, two nodes at creation."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].os_disk_type == "Managed" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].os_disk_size_gb == 30 &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].max_pods == 110 &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled == false
    )
    error_message = "Managed 30 GB OS disk (the VM size has no temp disk), 110 pods per node, apps allowed on the system pool."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.default_node_pool[0].upgrade_settings[0].max_surge == "1" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].temporary_name_for_rotation == "systemtmp"
    )
    error_message = "Upgrades surge one node at a time; property changes rotate the pool through systemtmp."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].tags == var.tags
    error_message = "The node pool (VM scale set) carries the contract tags."
  }
}

run "control_plane_logs_are_opt_in" {
  command = apply

  module {
    source = "../../modules/aks"
  }

  variables {
    enable_control_plane_logs = true
  }

  assert {
    condition = (
      azurerm_log_analytics_workspace.this[0].sku == "PerGB2018" &&
      azurerm_log_analytics_workspace.this[0].retention_in_days == 30 &&
      azurerm_log_analytics_workspace.this[0].daily_quota_gb == 0.5 &&
      azurerm_log_analytics_workspace.this[0].tags == var.tags
    )
    error_message = "The workspace must have a daily cap, the minimum retention and the contract tags."
  }

  assert {
    condition = (
      azurerm_monitor_diagnostic_setting.control_plane[0].target_resource_id == azurerm_kubernetes_cluster.this.id &&
      azurerm_monitor_diagnostic_setting.control_plane[0].log_analytics_workspace_id == azurerm_log_analytics_workspace.this[0].id &&
      azurerm_monitor_diagnostic_setting.control_plane[0].log_analytics_destination_type == "Dedicated" &&
      toset([for l in azurerm_monitor_diagnostic_setting.control_plane[0].enabled_log : l.category]) == toset(["kube-audit-admin", "guard"])
    )
    error_message = "Only kube-audit-admin and guard go to the workspace (resource-specific tables)."
  }

  assert {
    condition     = output.log_analytics_workspace_id == azurerm_log_analytics_workspace.this[0].id
    error_message = "The workspace ID must be an output."
  }
}

run "kubernetes_version_and_sizes_follow_the_variables" {
  command = plan

  module {
    source = "../../modules/aks"
  }

  variables {
    kubernetes_version = "1.37"
    node_vm_size       = "Standard_D4als_v6"
    node_max_count     = 5
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.this.kubernetes_version == "1.37" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size == "Standard_D4als_v6" &&
      azurerm_kubernetes_cluster.this.default_node_pool[0].max_count == 5
    )
    error_message = "Version, VM size and autoscaler bounds must come from the variables."
  }
}
