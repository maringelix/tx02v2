# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx02v2-lab). The server becomes <name>-postgres."
  type        = string
}

variable "location" {
  description = "Azure location of the server."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the server."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone (*.postgres.database.azure.com) linked to the VNet."
  type        = string
}

variable "sku_name" {
  description = "Compute SKU."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB."
  type        = number
  default     = 32768
}

variable "storage_tier" {
  description = "Premium SSD performance tier of the storage (P4 for 32 GB)."
  type        = string
  default     = "P4"
}

variable "backup_retention_days" {
  description = "Backup retention in days (7 is the minimum)."
  type        = number
  default     = 7
}

variable "database_name" {
  description = "Database of the app."
  type        = string
  default     = "dx02v2"
}

variable "administrator_login" {
  description = "Admin user (the lab app uses it, see docs/ARQUITETURA.md)."
  type        = string
  default     = "dx02v2_admin"
}

variable "administrator_password" {
  description = "Ephemeral admin password, sent only through administrator_password_wo."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "password_version" {
  description = "Increment to send a new password (drives administrator_password_wo_version)."
  type        = number
}

variable "tags" {
  description = "Contract tags."
  type        = map(string)
}
