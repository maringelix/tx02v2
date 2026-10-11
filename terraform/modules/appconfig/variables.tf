# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Globally unique store name (contract: tx02v2-lab-<suffix>)."
  type        = string
}

variable "location" {
  description = "Azure location of the store."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the store."
  type        = string
}

variable "key_prefix" {
  description = "Prefix of every key (contract: tx02v2/lab/)."
  type        = string
}

variable "keys" {
  description = "Contract key (without prefix) => value. Keys must be known at plan time."
  type        = map(string)
}

variable "tags" {
  description = "Contract tags (also set as tags of each key-value)."
  type        = map(string)
}
