# Inputs of the lab root. Cloud workflows pass them as TF_VAR_* repository variables
# (lists as JSON strings); docs/RUNBOOK.md lists every one. Every input is validated here; the
# modules trust what they receive.

variable "location" {
  description = "Azure location of the lab (contract key location). Must match the location of the tx02v2-lab resource group created by terraform/bootstrap."
  type        = string
  default     = "eastus2"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,30}$", var.location))
    error_message = "The location must be an Azure location name such as eastus2 or brazilsouth."
  }
}

variable "github_owner" {
  description = "GitHub owner of this repository; used in the Repository tag. The workflows pass github.repository_owner."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "The github_owner must be a valid GitHub user or organization name."
  }

  validation {
    condition     = lower(var.github_owner) != "your-github-user"
    error_message = "Set github_owner to the GitHub user that owns your forks (terraform.tfvars.example holds a placeholder)."
  }
}

# --- Identities and access ---

variable "deploy_principal_id" {
  description = "Object (principal) ID of the dx02v2-gha-deploy identity (bootstrap output deploy_principal_id). Gets AcrPush, AKS Cluster User Role and App Configuration Data Reader; the RoleBinding of platform/manifests uses it."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.deploy_principal_id))
    error_message = "The deploy_principal_id must be a lowercase GUID (object ID), e.g. 00000000-0000-0000-0000-000000000000."
  }
}

variable "cluster_admin_principal_ids" {
  description = "Object IDs (users, groups or identities) that get Azure Kubernetes Service RBAC Cluster Admin. Include the principal ID of tx02v2-gha-apply (platform and destroy workflows) and your own."
  type        = list(string)

  validation {
    condition     = length(var.cluster_admin_principal_ids) > 0
    error_message = "Set at least one cluster admin: local accounts are disabled, so nobody else can administer the cluster."
  }

  validation {
    condition     = alltrue([for id in var.cluster_admin_principal_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "Every cluster_admin_principal_ids entry must be a lowercase GUID (object ID)."
  }

  validation {
    condition     = length(distinct(var.cluster_admin_principal_ids)) == length(var.cluster_admin_principal_ids)
    error_message = "The cluster_admin_principal_ids entries must be unique."
  }

  validation {
    condition     = !contains(var.cluster_admin_principal_ids, var.deploy_principal_id)
    error_message = "dx02v2-gha-deploy must not be a cluster admin: it gets Kubernetes access only through the dx02v2-deployers RoleBinding (contract)."
  }
}

variable "app_deployer_principal_ids" {
  description = "Extra object IDs (people deploying dx02v2 from a laptop) bound to the Role dx02v2-deployer besides deploy_principal_id. They get the same Azure roles as dx02v2-gha-deploy: AcrPush on the registry, AKS Cluster User Role on the cluster and App Configuration Data Reader on the contract store."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.app_deployer_principal_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "Every app_deployer_principal_ids entry must be a lowercase GUID (object ID)."
  }

  validation {
    condition     = length(distinct(var.app_deployer_principal_ids)) == length(var.app_deployer_principal_ids) && !contains(var.app_deployer_principal_ids, var.deploy_principal_id)
    error_message = "The app_deployer_principal_ids entries must be unique and must not repeat deploy_principal_id (it is always a deployer)."
  }
}

# --- Kubernetes API endpoint ---

variable "api_server_authorized_ip_ranges" {
  description = "IPv4 CIDRs allowed to reach the public AKS API server, e.g. [\"203.0.113.10/32\"] (at most 200). Entra ID authentication and RBAC still apply."
  type        = list(string)

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) > 0 && length(var.api_server_authorized_ip_ranges) <= 200
    error_message = "Set between 1 and 200 CIDRs in api_server_authorized_ip_ranges, e.g. [\"<YOUR_IP>/32\"]."
  }

  validation {
    condition     = alltrue([for c in var.api_server_authorized_ip_ranges : can(regex("^[0-9.]+/[0-9]{1,2}$", c)) && try(cidrsubnet(c, 0, 0) == c, false)])
    error_message = "Every api_server_authorized_ip_ranges entry must be an IPv4 network in canonical form, e.g. 203.0.113.10/32 or 198.51.100.0/24."
  }

  validation {
    condition     = var.allow_api_server_from_anywhere || !contains(var.api_server_authorized_ip_ranges, "0.0.0.0/0")
    error_message = "The CIDR 0.0.0.0/0 opens the API server to the whole Internet: set allow_api_server_from_anywhere = true to accept it explicitly (GitHub-hosted runners need it, see docs/ARQUITETURA.md)."
  }
}

variable "allow_api_server_from_anywhere" {
  description = "Explicit opt-in required to use 0.0.0.0/0 in api_server_authorized_ip_ranges."
  type        = bool
  default     = false
}

# --- AKS ---

variable "kubernetes_version" {
  description = "Kubernetes minor version of AKS. 1.36 is supported by AKS until June 2027 (docs/SUSTENTACAO.md)."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "The kubernetes_version must be a Kubernetes minor version such as 1.36 (AKS applies the latest patch)."
  }
}

variable "node_vm_size" {
  description = "VM size of the system node pool: at least 2 vCPU and 4 GiB, x86-64 (the dx02v2 images are linux/amd64), not B-series. Standard_D2als_v6 is the cheapest that qualifies in eastus2 (docs/CUSTOS.md)."
  type        = string
  default     = "Standard_D2als_v6"

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.node_vm_size))
    error_message = "The node_vm_size must be an Azure VM size such as Standard_D2als_v6."
  }

  # learn.microsoft.com, "Quotas, VM size restrictions and region availability in AKS" and "Use
  # system node pools": B-series VMs are not supported for system node pools (verified 2026-10-11).
  validation {
    condition     = !startswith(var.node_vm_size, "Standard_B")
    error_message = "AKS does not support B-series VMs in a system node pool; use a size such as Standard_D2als_v6 (docs/CUSTOS.md)."
  }
}

variable "node_os_disk_type" {
  description = "Managed (default: Standard_D2als_v6 has no temp disk and no ephemeral OS disk support) or Ephemeral (only for sizes with a large enough cache or temp disk)."
  type        = string
  default     = "Managed"

  validation {
    condition     = contains(["Managed", "Ephemeral"], var.node_os_disk_type)
    error_message = "The node_os_disk_type must be Managed or Ephemeral."
  }
}

variable "node_os_disk_size_gb" {
  description = "OS disk of each node (30 GB = Premium SSD P4)."
  type        = number
  default     = 30

  validation {
    condition     = var.node_os_disk_size_gb >= 30 && var.node_os_disk_size_gb <= 256 && floor(var.node_os_disk_size_gb) == var.node_os_disk_size_gb
    error_message = "The node_os_disk_size_gb must be an integer between 30 and 256."
  }
}

variable "node_max_pods" {
  description = "Maximum pods per node (Azure CNI Overlay allows up to 250)."
  type        = number
  default     = 110

  validation {
    condition     = var.node_max_pods >= 30 && var.node_max_pods <= 250 && floor(var.node_max_pods) == var.node_max_pods
    error_message = "The node_max_pods must be an integer between 30 and 250."
  }
}

variable "node_count" {
  description = "Initial node count (later drift is ignored: the cluster autoscaler owns it)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_count <= var.node_count && var.node_count <= var.node_max_count && floor(var.node_count) == var.node_count
    error_message = "The node counts must satisfy node_min_count <= node_count <= node_max_count."
  }
}

variable "node_min_count" {
  description = "Cluster autoscaler minimum."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_count >= 1 && floor(var.node_min_count) == var.node_min_count
    error_message = "The node_min_count must be an integer >= 1 (a system pool cannot scale to zero)."
  }
}

variable "node_max_count" {
  description = "Cluster autoscaler maximum."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_count >= 1 && var.node_max_count <= 10 && floor(var.node_max_count) == var.node_max_count
    error_message = "The node_max_count must be an integer between 1 and 10."
  }
}

variable "enable_control_plane_logs" {
  description = "Send AKS kube-audit-admin and guard logs to a Log Analytics workspace (billed per GB ingested, docs/CUSTOS.md)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspaces: traces, and control plane logs when enabled (30 is the minimum of the PerGB2018 tier)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "The log_retention_days must be an integer between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap of each Log Analytics workspace and of the Application Insights of the traces (ingestion stops for the day when reached)."
  type        = number
  default     = 0.5

  validation {
    condition     = var.log_daily_quota_gb > 0 && var.log_daily_quota_gb <= 10
    error_message = "The log_daily_quota_gb must be greater than 0 and at most 10."
  }
}

# --- Network (all CIDRs validated, including overlaps) ---

variable "vnet_cidr" {
  description = "VNet address space (/16 to /22)."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-2])$", var.vnet_cidr)) && try(cidrsubnet(var.vnet_cidr, 0, 0) == var.vnet_cidr, false)
    error_message = "The vnet_cidr must be a canonical IPv4 network with a prefix between /16 and /22, e.g. 10.20.0.0/16."
  }
}

variable "aks_nodes_subnet_cidr" {
  description = "Subnet of the AKS nodes (inside vnet_cidr)."
  type        = string
  default     = "10.20.0.0/22"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-6])$", var.aks_nodes_subnet_cidr)) && try(cidrsubnet(var.aks_nodes_subnet_cidr, 0, 0) == var.aks_nodes_subnet_cidr, false)
    error_message = "The aks_nodes_subnet_cidr must be a canonical IPv4 network with a prefix between /16 and /26."
  }

  validation {
    condition = try(
      tonumber(split("/", var.aks_nodes_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) &&
      cidrhost("${split("/", var.aks_nodes_subnet_cidr)[0]}/${split("/", var.vnet_cidr)[1]}", 0) == split("/", var.vnet_cidr)[0],
    true)
    error_message = "The aks_nodes_subnet_cidr must be inside vnet_cidr."
  }
}

variable "agc_subnet_cidr" {
  description = "Subnet delegated to Application Gateway for Containers: exactly a /24 inside vnet_cidr (contract key agc-subnet-cidr; dx02v2 refuses any other prefix)."
  type        = string
  default     = "10.20.4.0/24"

  # With Azure CNI Overlay the AGC subnet must be a /24: a larger or smaller prefix is not
  # supported (learn.microsoft.com, "Container networking with Application Gateway for
  # Containers", Limitations; verified 2026-10-11).
  validation {
    condition     = can(regex("^[0-9.]+/24$", var.agc_subnet_cidr)) && try(cidrsubnet(var.agc_subnet_cidr, 0, 0) == var.agc_subnet_cidr, false)
    error_message = "The agc_subnet_cidr must be a canonical IPv4 /24 (Application Gateway for Containers with Azure CNI Overlay supports exactly /24), e.g. 10.20.4.0/24."
  }

  validation {
    condition = try(
      tonumber(split("/", var.agc_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) &&
      cidrhost("${split("/", var.agc_subnet_cidr)[0]}/${split("/", var.vnet_cidr)[1]}", 0) == split("/", var.vnet_cidr)[0],
    true)
    error_message = "The agc_subnet_cidr must be inside vnet_cidr."
  }

  validation {
    condition = try(
      cidrhost("${split("/", var.agc_subnet_cidr)[0]}/${min(tonumber(split("/", var.agc_subnet_cidr)[1]), tonumber(split("/", var.aks_nodes_subnet_cidr)[1]))}", 0) !=
      cidrhost("${split("/", var.aks_nodes_subnet_cidr)[0]}/${min(tonumber(split("/", var.agc_subnet_cidr)[1]), tonumber(split("/", var.aks_nodes_subnet_cidr)[1]))}", 0),
    true)
    error_message = "The agc_subnet_cidr must not overlap aks_nodes_subnet_cidr."
  }
}

variable "postgres_subnet_cidr" {
  description = "Subnet delegated to PostgreSQL Flexible Server (inside vnet_cidr; contract key postgres-subnet-cidr)."
  type        = string
  default     = "10.20.5.0/24"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-8])$", var.postgres_subnet_cidr)) && try(cidrsubnet(var.postgres_subnet_cidr, 0, 0) == var.postgres_subnet_cidr, false)
    error_message = "The postgres_subnet_cidr must be a canonical IPv4 network with a prefix between /16 and /28."
  }

  validation {
    condition = try(
      tonumber(split("/", var.postgres_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) &&
      cidrhost("${split("/", var.postgres_subnet_cidr)[0]}/${split("/", var.vnet_cidr)[1]}", 0) == split("/", var.vnet_cidr)[0],
    true)
    error_message = "The postgres_subnet_cidr must be inside vnet_cidr."
  }

  validation {
    condition = try(alltrue([
      for other in [var.aks_nodes_subnet_cidr, var.agc_subnet_cidr] :
      cidrhost("${split("/", var.postgres_subnet_cidr)[0]}/${min(tonumber(split("/", var.postgres_subnet_cidr)[1]), tonumber(split("/", other)[1]))}", 0) !=
      cidrhost("${split("/", other)[0]}/${min(tonumber(split("/", var.postgres_subnet_cidr)[1]), tonumber(split("/", other)[1]))}", 0)
    ]), true)
    error_message = "The postgres_subnet_cidr must not overlap aks_nodes_subnet_cidr or agc_subnet_cidr."
  }
}

variable "pod_cidr" {
  description = "Overlay pod CIDR of Azure CNI Overlay (must not overlap the VNet or service_cidr)."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/(1[0-9]|2[0-4])$", var.pod_cidr)) && try(cidrsubnet(var.pod_cidr, 0, 0) == var.pod_cidr, false)
    error_message = "The pod_cidr must be a canonical IPv4 network with a prefix between /10 and /24."
  }

  validation {
    condition = try(alltrue([
      for other in [var.vnet_cidr, var.service_cidr] :
      cidrhost("${split("/", var.pod_cidr)[0]}/${min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", other)[1]))}", 0) !=
      cidrhost("${split("/", other)[0]}/${min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", other)[1]))}", 0)
    ]), true)
    error_message = "The pod_cidr must not overlap vnet_cidr or service_cidr."
  }
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap the VNet)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-4])$", var.service_cidr)) && try(cidrsubnet(var.service_cidr, 0, 0) == var.service_cidr, false)
    error_message = "The service_cidr must be a canonical IPv4 network with a prefix between /16 and /24."
  }

  validation {
    condition = try(
      cidrhost("${split("/", var.service_cidr)[0]}/${min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))}", 0) !=
      cidrhost("${split("/", var.vnet_cidr)[0]}/${min(tonumber(split("/", var.service_cidr)[1]), tonumber(split("/", var.vnet_cidr)[1]))}", 0),
    true)
    error_message = "The service_cidr must not overlap vnet_cidr."
  }
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP: inside service_cidr, not its first two addresses."
  type        = string
  default     = "10.0.0.10"

  validation {
    condition = try(
      cidrhost("${var.dns_service_ip}/${split("/", var.service_cidr)[1]}", 0) == split("/", var.service_cidr)[0] &&
      !contains([cidrhost(var.service_cidr, 0), cidrhost(var.service_cidr, 1)], var.dns_service_ip) &&
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.dns_service_ip)),
    false)
    error_message = "The dns_service_ip must be an IPv4 address inside service_cidr other than its first two addresses, e.g. 10.0.0.10."
  }
}

# --- Edge, data stores, secrets ---

variable "enable_waf" {
  description = "WAF policy (DRS 2.1 + Bot Manager 1.1, Prevention) on Application Gateway for Containers. Parity with tx01v2; about US$0.12/h more than without WAF (docs/CUSTOS.md)."
  type        = bool
  default     = true
}

variable "postgres_backup_retention_days" {
  description = "PostgreSQL backup retention (7 is the minimum Azure accepts)."
  type        = number
  default     = 7

  validation {
    condition     = var.postgres_backup_retention_days >= 7 && var.postgres_backup_retention_days <= 35 && floor(var.postgres_backup_retention_days) == var.postgres_backup_retention_days
    error_message = "The postgres_backup_retention_days must be an integer between 7 and 35."
  }
}

variable "db_password_version" {
  description = "Increment to rotate the PostgreSQL password; it drives the server and the Key Vault secret together (write-only versions). Also bump it if a plan replaces the server."
  type        = number
  default     = 1

  validation {
    condition     = var.db_password_version >= 1 && floor(var.db_password_version) == var.db_password_version
    error_message = "The db_password_version must be a positive integer."
  }
}

variable "admin_token_version" {
  description = "Increment to generate a new dx02v2 admin token (write-only secret version)."
  type        = number
  default     = 1

  validation {
    condition     = var.admin_token_version >= 1 && floor(var.admin_token_version) == var.admin_token_version
    error_message = "The admin_token_version must be a positive integer."
  }
}

variable "purge_key_vault_on_destroy" {
  description = "Purge the soft-deleted Key Vault on destroy so its name is free at once. Needs a subscription-level purge permission (the subscription Owner has it; the CI apply identity does not), so it stays false in the workflows."
  type        = bool
  default     = false
}
