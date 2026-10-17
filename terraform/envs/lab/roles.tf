# Every Azure role assignment of the lab, in one place. The roles come only from
# modules/role-ids (lab_assignable), which is also the list the ABAC condition of
# tx02v2-gha-apply allows (terraform/bootstrap/roles.tf): tests/roles.tftest.hcl proves both sides
# match. Scopes are always resources inside the tx02v2-lab resource group, never the subscription.

locals {
  role_definition_prefix = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions"

  acr_repositories = toset(["dx02v2/api", "dx02v2/web"])

  acr_reader_conditions = {
    for repository in local.acr_repositories : repository => <<-EOT
      (
        (
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
          AND
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
        )
        OR
        (
          @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase '${repository}'
        )
      )
    EOT
  }

  acr_writer_conditions = {
    for repository in local.acr_repositories : repository => <<-EOT
      (
        (
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
          AND
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
          AND
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/write'})
          AND
          !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/write'})
        )
        OR
        (
          @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringEqualsIgnoreCase '${repository}'
        )
      )
    EOT
  }

  acr_reader_principals = {
    kubelet = azurerm_user_assigned_identity.kubelet.principal_id
    trivy   = azurerm_user_assigned_identity.trivy.principal_id
    kyverno = azurerm_user_assigned_identity.kyverno.principal_id
  }

  image_writer_principals = merge(
    { deploy = var.deploy_principal_id },
    { for id in var.app_deployer_principal_ids : "app-${id}" => id },
  )

  # Contract: dx02v2-gha-deploy and every app_deployer_principal_ids entry (people deploying
  # dx02v2 from a laptop) get repository-scoped image writer access, a kubeconfig, and contract
  # store read access. Nothing on Key Vault; Kubernetes access comes only from the dx02v2-deployers
  # RoleBinding (platform/manifests).
  deployer_roles = {
    "aks-cluster-user" = { role = "Azure Kubernetes Service Cluster User Role", scope = module.aks.cluster_id }
    "appconfig-reader" = { role = "App Configuration Data Reader", scope = module.appconfig.id }
  }

  role_assignments = merge(
    {
      # External Secrets Operator reads the two lab secrets (this vault only).
      "eso-keyvault-secrets-user" = {
        role           = "Key Vault Secrets User"
        scope          = module.keyvault.id
        principal_id   = azurerm_user_assigned_identity.eso.principal_id
        principal_type = "ServicePrincipal"
      }
      # ALB Controller, bring-your-own deployment (AGC quickstart): configure the AGC of this
      # resource group and join its delegated subnet.
      "alb-agc-configuration-manager" = {
        role           = "AppGw for Containers Configuration Manager"
        scope          = data.azurerm_resource_group.lab.id
        principal_id   = azurerm_user_assigned_identity.alb.principal_id
        principal_type = "ServicePrincipal"
      }
      "alb-agc-subnet-network-contributor" = {
        role           = "Network Contributor"
        scope          = module.network.agc_subnet_id
        principal_id   = azurerm_user_assigned_identity.alb.principal_id
        principal_type = "ServicePrincipal"
      }
      # OpenTelemetry Collector (contract v2): writes the traces of the app to this Application
      # Insights resource only (Entra ID ingestion; local authentication is off, tracing.tf).
      "otel-monitoring-metrics-publisher" = {
        role           = "Monitoring Metrics Publisher"
        scope          = azurerm_application_insights.traces.id
        principal_id   = azurerm_user_assigned_identity.otel.principal_id
        principal_type = "ServicePrincipal"
      }
      # Velero writes backups only to its private Blob container; no account keys or account-wide role.
      "velero-blob-data-contributor" = {
        role           = "Storage Blob Data Contributor"
        scope          = module.velero.container_id
        principal_id   = module.velero.identity_principal_id
        principal_type = "ServicePrincipal"
      }
    },
    # Nodes, Trivy scan jobs, and Kyverno admission read only the two app repositories. ACR with
    # ABAC repository permissions has no catalog-list permission unless one is assigned explicitly.
    {
      for pair in setproduct(keys(local.acr_reader_principals), local.acr_repositories) :
      "acr-reader-${pair[0]}-${replace(pair[1], "/", "-")}" => {
        role              = "Container Registry Repository Reader"
        scope             = module.acr.id
        principal_id      = local.acr_reader_principals[pair[0]]
        principal_type    = "ServicePrincipal"
        condition         = local.acr_reader_conditions[pair[1]]
        condition_version = "2.0"
      }
    },
    # The deploy identity and laptop deployers can push only to the API and web repositories.
    {
      for pair in setproduct(keys(local.image_writer_principals), local.acr_repositories) :
      "image-writer-${pair[0]}-${replace(pair[1], "/", "-")}" => {
        role              = "Container Registry Repository Writer"
        scope             = module.acr.id
        principal_id      = local.image_writer_principals[pair[0]]
        principal_type    = null
        condition         = local.acr_writer_conditions[pair[1]]
        condition_version = "2.0"
      }
    },
    # dx02v2-gha-deploy, a managed identity.
    {
      for k, r in local.deployer_roles : "deploy-${k}" => {
        role           = r.role
        scope          = r.scope
        principal_id   = var.deploy_principal_id
        principal_type = "ServicePrincipal"
      }
    },
    # Cluster administrators through Azure RBAC (local accounts are disabled).
    {
      for id in var.cluster_admin_principal_ids : "cluster-admin-${id}" => {
        role           = "Azure Kubernetes Service RBAC Cluster Admin"
        scope          = module.aks.cluster_id
        principal_id   = id
        principal_type = null
      }
    },
    # Extra deployers: the same roles as dx02v2-gha-deploy. They can be users, groups or
    # identities, so Azure determines the principal type.
    {
      for pair in setproduct(var.app_deployer_principal_ids, keys(local.deployer_roles)) : "app-deployer-${pair[1]}-${pair[0]}" => {
        role           = local.deployer_roles[pair[1]].role
        scope          = local.deployer_roles[pair[1]].scope
        principal_id   = pair[0]
        principal_type = null
      }
    },
  )
}

# Created before the cluster (module.aks depends on them): with a user-assigned control plane
# identity, AKS joins the node subnet and assigns the kubelet identity with it.
resource "azurerm_role_assignment" "pre_cluster" {
  for_each = {
    "aks-control-plane-node-subnet" = {
      role  = "Network Contributor"
      scope = module.network.aks_nodes_subnet_id
    }
    "aks-control-plane-kubelet-identity" = {
      role  = "Managed Identity Operator"
      scope = azurerm_user_assigned_identity.kubelet.id
    }
  }

  scope              = each.value.scope
  role_definition_id = "${local.role_definition_prefix}/${module.roles.lab_assignable[each.value.role]}"
  principal_id       = azurerm_user_assigned_identity.aks.principal_id
  principal_type     = "ServicePrincipal"
  description        = "tx02v2-lab: ${each.key}"
}

resource "azurerm_role_assignment" "lab" {
  for_each = local.role_assignments

  scope              = each.value.scope
  role_definition_id = "${local.role_definition_prefix}/${module.roles.lab_assignable[each.value.role]}"
  principal_id       = each.value.principal_id
  principal_type     = each.value.principal_type
  description        = "tx02v2-lab: ${each.key}"
  condition          = try(each.value.condition, null)
  condition_version  = try(each.value.condition_version, null)
}
