variable "name" {
  description = "Prefix of the lab resources, for example tx02v2-lab."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique lowercase StorageV2 account name (3-24 alphanumeric characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "The Velero storage account name must contain 3-24 lowercase letters or digits."
  }
}

variable "container_name" {
  description = "Private Blob container for Kubernetes resource backups."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.container_name))
    error_message = "The Velero container name must be 3-63 lowercase letters, digits or hyphens."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "aks_nodes_subnet_id" {
  description = "Only the AKS node subnet may reach the Storage account through its Microsoft.Storage service endpoint."
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the AKS cluster for the Velero Workload Identity."
  type        = string
}

variable "tags" {
  description = "Contract tags for resources that support Azure tags."
  type        = map(string)
}
variable "replication_type" {
  description = "LRS for core, RA-GRS for region-independent recovery reads in DR."
  type        = string
  default     = "LRS"
}

variable "recovery_subnet_ids" {
  description = "Additional owned recovery node subnets, never public IP ranges."
  type        = list(string)
  default     = []
}
