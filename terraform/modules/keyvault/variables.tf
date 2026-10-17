# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "manage_values" {
  description = "Primary values are write-only Terraform resources; DR is filled from current primary values by protected apply."
  type        = bool
  default     = true
}

variable "name" {
  description = "Globally unique vault name (contract: tx02v2-lab-<suffix>, at most 24 characters)."
  type        = string
}

variable "name_prefix" {
  description = "Prefix of the secret names (tx02v2-lab)."
  type        = string
}

variable "location" {
  description = "Azure location of the vault."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the vault."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant of the vault."
  type        = string
}

variable "db_secret_value" {
  description = "Ephemeral JSON of the database credentials (username, password, host, port, dbname)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "db_secret_version" {
  description = "Write-only version of the database secret (bumped together with the server password)."
  type        = number
}

variable "admin_token" {
  description = "Ephemeral admin token of dx02v2."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "admin_token_version" {
  description = "Write-only version of the admin token secret."
  type        = number
}

variable "tags" {
  description = "Contract tags."
  type        = map(string)
}
