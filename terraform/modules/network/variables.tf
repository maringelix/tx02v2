# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx02v2-lab)."
  type        = string
}

variable "location" {
  description = "Azure location of the VNet."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the network resources (tx02v2-lab)."
  type        = string
}

variable "vnet_cidr" {
  description = "Address space of the VNet."
  type        = string
}

variable "aks_nodes_subnet_cidr" {
  description = "Subnet of the AKS nodes (pods use the overlay pod CIDR, not this subnet)."
  type        = string
}

variable "agc_subnet_cidr" {
  description = "Subnet delegated to Application Gateway for Containers (exactly /24 with Azure CNI Overlay)."
  type        = string
}

variable "postgres_subnet_cidr" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "postgres_peer_cidr" {
  description = "Optional PostgreSQL subnet of the peered DR VNet; permits only TCP/5432 for private read-replica synchronization."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Contract tags applied to every taggable resource."
  type        = map(string)
}
variable "storage_service_endpoint" {
  description = "Microsoft.Storage.Global permits recovery from the paired storage region; ordinary labs stay regional."
  type        = string
  default     = "Microsoft.Storage"
  validation {
    condition     = contains(["Microsoft.Storage", "Microsoft.Storage.Global"], var.storage_service_endpoint)
    error_message = "Use the regional or global Microsoft Storage service endpoint."
  }
}
