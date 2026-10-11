# Inputs are validated by the calling root (terraform/envs/lab); this module trusts them.

variable "name" {
  description = "Name prefix of the lab (tx02v2-lab)."
  type        = string
}

variable "location" {
  description = "Azure location (the WAF policy must be in the same region as the AGC)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the AGC resources."
  type        = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.ServiceNetworking/trafficControllers."
  type        = string
}

variable "enable_waf" {
  description = "Create the WAF policy and the AGC SecurityPolicy."
  type        = bool
}

variable "tags" {
  description = "Contract tags."
  type        = map(string)
}
