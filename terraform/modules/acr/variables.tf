# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Globally unique registry name (contract: tx02v2lab<suffix>, alphanumeric)."
  type        = string
}

variable "location" {
  description = "Azure location of the registry."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the registry."
  type        = string
}

variable "tags" {
  description = "Contract tags."
  type        = map(string)
}
