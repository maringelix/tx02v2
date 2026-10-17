# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.
variable "enable_spot_pool" {
  description = "Opt-in tainted disposable user pool; the system pool stays on-demand."
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Operator bid ceiling USD/node-hour, not a price forecast."
  type        = number
  default     = 0.1
}

variable "name" {
  description = "Cluster name and name prefix (tx02v2-lab)."
  type        = string
}

variable "location" {
  description = "Azure location of the cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the cluster (tx02v2-lab)."
  type        = string
}

variable "node_resource_group" {
  description = "Name of the node resource group AKS creates and owns (contract: tx02v2-lab-nodes)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. \"1.36\" (AKS applies the latest patch)."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant of the cluster users."
  type        = string
}

variable "control_plane_identity_id" {
  description = "Resource ID of the user-assigned identity of the control plane."
  type        = string
}

variable "kubelet_identity" {
  description = "User-assigned identity of the kubelets: resource ID, client ID and object (principal) ID."
  type = object({
    id        = string
    client_id = string
    object_id = string
  })
}

variable "subnet_id" {
  description = "Subnet of the nodes."
  type        = string
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the public API server."
  type        = list(string)
}

variable "pod_cidr" {
  description = "Overlay pod CIDR (must not overlap the VNet)."
  type        = string
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap the VNet)."
  type        = string
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP (inside service_cidr)."
  type        = string
}

variable "node_vm_size" {
  description = "VM size of the system node pool."
  type        = string
}

variable "node_os_disk_type" {
  description = "Managed or Ephemeral (Ephemeral needs a VM size with a large enough cache or temp disk)."
  type        = string
}

variable "node_os_disk_size_gb" {
  description = "OS disk size of each node."
  type        = number
}

variable "node_max_pods" {
  description = "Maximum pods per node."
  type        = number
}

variable "node_count" {
  description = "Initial node count (later drift is ignored: the autoscaler owns it)."
  type        = number
}

variable "node_min_count" {
  description = "Autoscaler minimum."
  type        = number
}

variable "node_max_count" {
  description = "Autoscaler maximum."
  type        = number
}

variable "enable_control_plane_logs" {
  description = "Send kube-audit-admin and guard logs to a Log Analytics workspace (billed per GB)."
  type        = bool
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace."
  type        = number
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap of the Log Analytics workspace."
  type        = number
}

variable "tags" {
  description = "Contract tags applied to every taggable resource (and to the node pool VMSS)."
  type        = map(string)
}
