# Root-level wiring of the lab: lab-friendly defaults, contract names, the contract keys written
# to App Configuration and the outputs dx02v2 and platform/install.sh consume.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner                    = "maringelix"
  api_server_authorized_ip_ranges = ["203.0.113.10/32", "198.51.100.0/24"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]
}

run "defaults_are_lab_friendly" {
  command = plan

  assert {
    condition     = var.location == "eastus2" && var.kubernetes_version == "1.36" && var.enable_waf
    error_message = "Defaults: eastus2, Kubernetes 1.36 and WAF on (parity with tx01v2)."
  }

  assert {
    condition     = var.node_vm_size == "Standard_D2als_v6" && var.node_count == 2 && var.node_min_count == 1 && var.node_max_count == 3
    error_message = "Nodes default to Standard_D2als_v6, 2 nodes, autoscaler 1-3."
  }

  assert {
    condition     = var.enable_control_plane_logs == false && var.allow_api_server_from_anywhere == false && var.purge_key_vault_on_destroy == false
    error_message = "Control plane logs (billed per GB), an API server open to the world and the subscription-level purge must all be opt-in."
  }

  assert {
    condition     = var.postgres_backup_retention_days == 7 && length(var.app_deployer_principal_ids) == 0
    error_message = "PostgreSQL keeps the minimum 7 days of backups; no extra deployer by default."
  }

  assert {
    condition = (
      var.vnet_cidr == "10.20.0.0/16" && var.aks_nodes_subnet_cidr == "10.20.0.0/22" &&
      var.agc_subnet_cidr == "10.20.4.0/24" && var.postgres_subnet_cidr == "10.20.5.0/24" &&
      var.pod_cidr == "10.244.0.0/16" && var.service_cidr == "10.0.0.0/16" && var.dns_service_ip == "10.0.0.10"
    )
    error_message = "Network defaults changed: update docs/CONTRATO.md and dx02v2 together."
  }

  assert {
    condition     = local.tags == { Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" }
    error_message = "The tags must match the contract."
  }

  assert {
    condition = (
      local.suffix == "b602d594" &&
      local.keyvault_name == "tx02v2-lab-b602d594" &&
      local.appconfig_name == "tx02v2-lab-b602d594" &&
      local.acr_name == "tx02v2labb602d594" &&
      local.node_resource_group == "tx02v2-lab-nodes"
    )
    error_message = "Globally unique names use suffix = substr(sha1(subscription_id), 0, 8) (contract)."
  }

  assert {
    condition     = local.postgres_name_prefix == "tx02v2-lab-b602d594" && module.postgres.server_name == "tx02v2-lab-b602d594-postgres"
    error_message = "The PostgreSQL server name is a global DNS name: it carries the suffix, or the lab of one fork blocks the apply of every other one."
  }
}

run "contract_keys_in_app_configuration" {
  command = apply

  assert {
    condition = module.appconfig.key_names == sort([
      "tx02v2/lab/location",
      "tx02v2/lab/resource-group",
      "tx02v2/lab/cluster-name",
      "tx02v2/lab/vnet-cidr",
      "tx02v2/lab/agc-subnet-cidr",
      "tx02v2/lab/postgres-subnet-cidr",
      "tx02v2/lab/acr/login-server",
      "tx02v2/lab/keyvault/uri",
      "tx02v2/lab/db/secret-name",
      "tx02v2/lab/app/admin-token-secret-name",
      "tx02v2/lab/eso/cluster-secret-store",
      "tx02v2/lab/agc/id",
      "tx02v2/lab/agc/frontend-name",
      "tx02v2/lab/dns/hostname",
      "tx02v2/lab/dns/acme-email",
      "tx02v2/lab/waf/policy-id",
      "tx02v2/lab/deploy/principal-id",
    ])
    error_message = "The lab must publish exactly the seventeen contract keys under tx02v2/lab/."
  }

  assert {
    condition = local.contract_keys == {
      "location"                    = "eastus2"
      "resource-group"              = "tx02v2-lab"
      "cluster-name"                = "tx02v2-lab"
      "vnet-cidr"                   = "10.20.0.0/16"
      "agc-subnet-cidr"             = "10.20.4.0/24"
      "postgres-subnet-cidr"        = "10.20.5.0/24"
      "acr/login-server"            = "tx02v2labb602d594.azurecr.io"
      "keyvault/uri"                = "https://tx02v2-lab-b602d594.vault.azure.net/"
      "db/secret-name"              = "tx02v2-lab-db-app"
      "app/admin-token-secret-name" = "tx02v2-lab-app-admin-token"
      "eso/cluster-secret-store"    = "azure-key-vault"
      "agc/id"                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc"
      "agc/frontend-name"           = "tx02v2-lab-frontend"
      "dns/hostname"                = "disabled"
      "dns/acme-email"              = "disabled"
      "waf/policy-id"               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/tx02v2-lab-waf"
      "deploy/principal-id"         = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    }
    error_message = "Contract values must come from the modules and match docs/CONTRATO.md."
  }

  assert {
    condition     = output.appconfig_endpoint == "https://tx02v2-lab-b602d594.azconfig.io"
    error_message = "appconfig_endpoint becomes the dx02v2 variable AZURE_APPCONFIG_ENDPOINT."
  }

  assert {
    condition     = output.get_credentials_command == "az aks get-credentials --resource-group tx02v2-lab --name tx02v2-lab --file /tmp/tx02v2-lab.kubeconfig --overwrite-existing && kubelogin convert-kubeconfig -l azurecli --kubeconfig /tmp/tx02v2-lab.kubeconfig"
    error_message = "get_credentials_command must write the kubeconfig to its own file and convert only that file for kubelogin (local accounts are disabled); ~/.kube/config is never touched."
  }

  assert {
    condition     = module.aks.api_server_authorized_ip_ranges == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "api_server_authorized_ip_ranges must reach the cluster unchanged."
  }

  assert {
    condition     = module.aks.node_resource_group == "tx02v2-lab-nodes" && output.node_resource_group == "tx02v2-lab-nodes"
    error_message = "The node resource group must be tx02v2-lab-nodes (contract)."
  }
}
