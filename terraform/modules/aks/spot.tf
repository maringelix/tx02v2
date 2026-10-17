# Optional disposable user capacity. The system pool remains regular/on-demand.
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count = var.enable_spot_pool ? 1 : 0

  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.node_vm_size
  vnet_subnet_id        = var.subnet_id
  os_sku                = "AzureLinux"
  os_disk_type          = var.node_os_disk_type
  os_disk_size_gb       = var.node_os_disk_size_gb
  max_pods              = var.node_max_pods
  mode                  = "User"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = var.spot_max_price
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 2
  node_count            = 0
  node_labels           = { "lab.capacity/pool" = "spot" }
  node_taints           = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
  tags                  = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}
