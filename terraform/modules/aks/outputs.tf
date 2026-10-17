output "cluster_id" {
  description = "AKS cluster resource ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "kubernetes_version" {
  description = "Configured Kubernetes minor version."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

output "oidc_issuer_url" {
  description = "OIDC issuer of the cluster (federated credentials of the workload identities)."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_object_id" {
  description = "Object ID of the kubelet identity configured on the cluster (repository-scoped ACR Reader)."
  value       = var.kubelet_identity.object_id
}

output "node_resource_group" {
  description = "Node resource group created and owned by AKS."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "api_server_authorized_ip_ranges" {
  description = "Authorized IP ranges as configured on the cluster."
  value       = azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace of the control plane logs, or null when they are disabled."
  value       = one(azurerm_log_analytics_workspace.this[*].id)
}
