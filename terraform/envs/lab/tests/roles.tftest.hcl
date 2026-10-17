# Every role assignment of the lab root (roles.tf) and the federated credentials of the platform
# controllers. The set of roles used here must equal the ABAC list of tx02v2-gha-apply
# (terraform/bootstrap/tests/roles.tftest.hcl): both come from modules/role-ids.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner                    = "maringelix"
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]
  app_deployer_principal_ids      = ["eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"]
}

# Distinct IDs for the instances that share a mock default (override_resource replaces the
# defaults, so every consumed computed value is set).
override_resource {
  target = azurerm_user_assigned_identity.aks
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-aks"
    principal_id = "33333333-3333-3333-3333-333333333333"
    client_id    = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.eso
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-eso"
    principal_id = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    client_id    = "55555555-5555-5555-5555-555555555555"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.alb
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-alb"
    principal_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
    client_id    = "66666666-6666-6666-6666-666666666666"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.otel
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-otel"
    principal_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    client_id    = "99999999-9999-9999-9999-999999999999"
  }
}

override_resource {
  target = module.velero.azurerm_user_assigned_identity.velero
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-velero"
    principal_id = "33333333-3333-3333-3333-333333333333"
    client_id    = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target = module.velero.azurerm_storage_account.this
  values = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Storage/storageAccounts/tx02v2labb602d594velero"
    name = "tx02v2labb602d594velero"
  }
}

override_resource {
  target = module.velero.azurerm_storage_container.backups
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Storage/storageAccounts/tx02v2labb602d594velero/blobServices/default/containers/tx02v2-lab-velero"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.kubelet
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-kubelet"
    principal_id = "77777777-7777-7777-7777-777777777777"
    client_id    = "88888888-8888-8888-8888-888888888888"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.trivy
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-trivy"
    principal_id = "55555555-5555-5555-5555-555555555555"
    client_id    = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.kyverno
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-kyverno"
    principal_id = "66666666-6666-6666-6666-666666666666"
    client_id    = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
  }
}

override_resource {
  target = module.network.azurerm_subnet.aks_nodes
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/aks-nodes" }
}

override_resource {
  target = module.network.azurerm_subnet.agc
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/agc" }
}

override_resource {
  target = module.network.azurerm_subnet.postgres
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/postgres" }
}

run "the_lab_assigns_exactly_the_abac_roles" {
  command = apply

  assert {
    condition = toset(concat(
      [for r in azurerm_role_assignment.pre_cluster : basename(r.role_definition_id)],
      [for r in azurerm_role_assignment.lab : basename(r.role_definition_id)],
    )) == toset(values(module.roles.lab_assignable))
    error_message = "The roles assigned by the lab root must equal the ABAC list of tx02v2-gha-apply (modules/role-ids)."
  }

  assert {
    condition = alltrue([
      for r in concat(values(azurerm_role_assignment.pre_cluster), values(azurerm_role_assignment.lab)) :
      startswith(r.role_definition_id, "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/")
    ])
    error_message = "Role definitions are referenced by ID (no name lookups, nothing outside modules/role-ids)."
  }

  assert {
    condition = alltrue([
      for r in concat(values(azurerm_role_assignment.pre_cluster), values(azurerm_role_assignment.lab)) :
      r.scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab" ||
      startswith(r.scope, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/")
    ])
    error_message = "Every lab role assignment must be scoped to tx02v2-lab or a resource inside it (never the subscription)."
  }

  assert {
    condition = { for k, r in azurerm_role_assignment.lab : k => "${basename(r.role_definition_id)} ${r.principal_id} ${r.scope}" if !strcontains(k, "acr-reader-") && !startswith(k, "image-writer-") } == {
      "deploy-aks-cluster-user"                                            = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f dddddddd-dddd-dddd-dddd-dddddddddddd /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "deploy-appconfig-reader"                                            = "516239f1-63e1-4d78-a4de-a74fb236a071 dddddddd-dddd-dddd-dddd-dddddddddddd /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.AppConfiguration/configurationStores/tx02v2-lab-b602d594"
      "eso-keyvault-secrets-user"                                          = "4633458b-17de-408a-b874-0445c86b69e6 cccccccc-cccc-cccc-cccc-cccccccccccc /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.KeyVault/vaults/tx02v2-lab-b602d594"
      "alb-agc-configuration-manager"                                      = "fbc52c3f-28ad-4303-a892-8a056630b8f1 ffffffff-ffff-ffff-ffff-ffffffffffff /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
      "alb-agc-subnet-network-contributor"                                 = "4d97b98b-1d4f-4787-a291-c67834d212e7 ffffffff-ffff-ffff-ffff-ffffffffffff /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/agc"
      "otel-monitoring-metrics-publisher"                                  = "3913510d-42f4-4e42-8a64-420c390055eb bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Insights/components/tx02v2-lab-traces"
      "velero-blob-data-contributor"                                       = "ba92f5b4-2d11-453d-a403-e96b0029c9fe 33333333-3333-3333-3333-333333333333 /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Storage/storageAccounts/tx02v2labb602d594velero/blobServices/default/containers/tx02v2-lab-velero"
      "cluster-admin-11111111-1111-1111-1111-111111111111"                 = "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b 11111111-1111-1111-1111-111111111111 /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "cluster-admin-22222222-2222-2222-2222-222222222222"                 = "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b 22222222-2222-2222-2222-222222222222 /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "app-deployer-aks-cluster-user-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee" = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "app-deployer-appconfig-reader-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee" = "516239f1-63e1-4d78-a4de-a74fb236a071 eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.AppConfiguration/configurationStores/tx02v2-lab-b602d594"
    }
    error_message = "Lab role assignments must match docs/CONTRATO.md and docs/ARQUITETURA.md exactly."
  }

  assert {
    condition = (
      length([for r in values(azurerm_role_assignment.lab) : r if r.condition != null]) == 10 &&
      alltrue([
        for r in values(azurerm_role_assignment.lab) :
        r.scope == module.acr.id && r.condition_version == "2.0" &&
        length([for repository in local.acr_repositories : repository if strcontains(r.condition, "'${repository}'")]) == 1
        if r.condition != null
      ]) &&
      alltrue(flatten([
        for principal in [
          azurerm_user_assigned_identity.kubelet.principal_id,
          azurerm_user_assigned_identity.trivy.principal_id,
          azurerm_user_assigned_identity.kyverno.principal_id,
          ] : [
          for repository in local.acr_repositories : length([
            for r in values(azurerm_role_assignment.lab) : r
            if r.principal_id == principal &&
            basename(r.role_definition_id) == module.roles.lab_assignable["Container Registry Repository Reader"] &&
            strcontains(r.condition, "'${repository}'")
          ]) == 1
        ]
      ])) &&
      alltrue(flatten([
        for principal in concat([var.deploy_principal_id], var.app_deployer_principal_ids) : [
          for repository in local.acr_repositories : length([
            for r in values(azurerm_role_assignment.lab) : r
            if r.principal_id == principal &&
            basename(r.role_definition_id) == module.roles.lab_assignable["Container Registry Repository Writer"] &&
            strcontains(r.condition, "'${repository}'")
          ]) == 1
        ]
      ]))
    )
    error_message = "Kubelet, Trivy and Kyverno read each app repository; deploy identities write each app repository, using condition version 2.0 and no catalog-wide grant."
  }

  assert {
    condition = alltrue([
      for r in values(azurerm_role_assignment.lab) :
      basename(r.role_definition_id) == module.roles.lab_assignable["Container Registry Repository Reader"] ? (
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})") &&
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})") &&
        !strcontains(r.condition, "repositories/content/write")
        ) : (
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})") &&
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})") &&
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/write'})") &&
        strcontains(r.condition, "!(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/write'})")
      )
      if r.condition != null
    ])
    error_message = "ACR reader and writer ABAC conditions must constrain every data action granted by their built-in role."
  }

  assert {
    condition = { for k, r in azurerm_role_assignment.pre_cluster : k => "${basename(r.role_definition_id)} ${r.principal_id} ${r.scope}" } == {
      "aks-control-plane-node-subnet"      = "4d97b98b-1d4f-4787-a291-c67834d212e7 33333333-3333-3333-3333-333333333333 /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/aks-nodes"
      "aks-control-plane-kubelet-identity" = "f1a07417-d97a-45cb-824c-7a7467783830 33333333-3333-3333-3333-333333333333 /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-kubelet"
    }
    error_message = "Before the cluster, the control plane identity gets Network Contributor on the node subnet and Managed Identity Operator on the kubelet identity, nothing else."
  }

  assert {
    condition = alltrue([
      for r in values(azurerm_role_assignment.lab) :
      !(contains(["dddddddd-dddd-dddd-dddd-dddddddddddd", "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"], r.principal_id) && strcontains(r.scope, "Microsoft.KeyVault"))
    ])
    error_message = "Deployers (dx02v2-gha-deploy and app_deployer_principal_ids) get nothing on Key Vault (contract): ESO reads the secrets."
  }
}

# Contract: every app_deployer_principal_ids entry gets exactly the Azure roles of
# dx02v2-gha-deploy, on the same scopes, and the ABAC list still equals what the lab assigns.
run "app_deployers_get_the_roles_of_the_deploy_identity" {
  command = apply

  variables {
    app_deployer_principal_ids = ["eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
  }

  assert {
    condition = alltrue([
      for id in ["eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"] :
      toset([for r in values(azurerm_role_assignment.lab) : "${basename(r.role_definition_id)} ${r.scope}" if r.principal_id == id]) ==
      toset([for r in values(azurerm_role_assignment.lab) : "${basename(r.role_definition_id)} ${r.scope}" if r.principal_id == "dddddddd-dddd-dddd-dddd-dddddddddddd"])
    ])
    error_message = "Each app deployer must get exactly the roles and scopes of dx02v2-gha-deploy."
  }

  assert {
    condition = { for k, r in azurerm_role_assignment.lab : k => "${basename(r.role_definition_id)} ${r.principal_id} ${r.scope}" if startswith(k, "app-deployer-") } == {
      "app-deployer-aks-cluster-user-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee" = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "app-deployer-appconfig-reader-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee" = "516239f1-63e1-4d78-a4de-a74fb236a071 eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.AppConfiguration/configurationStores/tx02v2-lab-b602d594"
      "app-deployer-aks-cluster-user-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      "app-deployer-appconfig-reader-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" = "516239f1-63e1-4d78-a4de-a74fb236a071 aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.AppConfiguration/configurationStores/tx02v2-lab-b602d594"
    }
    error_message = "App deployers get repository-scoped ACR writer access, AKS Cluster User Role and App Configuration Data Reader, nothing else."
  }

  assert {
    condition = toset(concat(
      [for r in azurerm_role_assignment.pre_cluster : basename(r.role_definition_id)],
      [for r in azurerm_role_assignment.lab : basename(r.role_definition_id)],
    )) == toset(values(module.roles.lab_assignable))
    error_message = "With app deployers, the roles assigned by the lab root must still equal the ABAC list of tx02v2-gha-apply."
  }

  assert {
    condition     = length(azurerm_role_assignment.lab) == 25
    error_message = "Lab role assignments include six ACR readers, two repository writers per deploy identity, controllers, cluster admins and three roles per app deployer (2)."
  }
}

# Without app deployers nothing extra is assigned, and the ABAC list (which never changes with
# the inputs) still equals the roles of the lab root: no role may become unassigned.
run "no_app_deployers_assign_nothing_extra" {
  command = apply

  variables {
    app_deployer_principal_ids = []
  }

  assert {
    condition     = length([for k in keys(azurerm_role_assignment.lab) : k if startswith(k, "app-deployer-") || startswith(k, "image-writer-app-")]) == 0
    error_message = "An empty app_deployer_principal_ids must not create role assignments."
  }

  assert {
    condition = toset(concat(
      [for r in azurerm_role_assignment.pre_cluster : basename(r.role_definition_id)],
      [for r in azurerm_role_assignment.lab : basename(r.role_definition_id)],
    )) == toset(values(module.roles.lab_assignable))
    error_message = "Without app deployers, the roles assigned by the lab root must still equal the ABAC list of tx02v2-gha-apply."
  }

  assert {
    condition = { for k, r in azurerm_role_assignment.lab : k => "${basename(r.role_definition_id)} ${r.principal_id}" if startswith(k, "deploy-") } == {
      "deploy-aks-cluster-user" = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f dddddddd-dddd-dddd-dddd-dddddddddddd"
      "deploy-appconfig-reader" = "516239f1-63e1-4d78-a4de-a74fb236a071 dddddddd-dddd-dddd-dddd-dddddddddddd"
    }
    error_message = "dx02v2-gha-deploy keeps its cluster and contract roles plus two repository-scoped writer assignments without app deployers."
  }

  assert {
    condition     = length(azurerm_role_assignment.lab) == 17
    error_message = "Without app deployers the lab assigns 17 roles after the cluster exists (six ACR readers, two deploy writers and the remaining lab/controller roles)."
  }
}

run "controller_identities_are_federated_with_the_cluster" {
  command = apply

  assert {
    condition = (
      azurerm_federated_identity_credential.eso.user_assigned_identity_id == azurerm_user_assigned_identity.eso.id &&
      azurerm_federated_identity_credential.eso.subject == "system:serviceaccount:external-secrets:external-secrets" &&
      azurerm_federated_identity_credential.eso.issuer == "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/55555555-5555-5555-5555-555555555555/" &&
      azurerm_federated_identity_credential.eso.audience == tolist(["api://AzureADTokenExchange"])
    )
    error_message = "tx02v2-lab-eso must trust only external-secrets/external-secrets from the AKS OIDC issuer (contract)."
  }

  assert {
    condition = (
      azurerm_federated_identity_credential.alb.name == "azure-alb-identity" &&
      azurerm_federated_identity_credential.alb.user_assigned_identity_id == azurerm_user_assigned_identity.alb.id &&
      azurerm_federated_identity_credential.alb.subject == "system:serviceaccount:azure-alb-system:alb-controller-sa" &&
      azurerm_federated_identity_credential.alb.issuer == module.aks.oidc_issuer_url &&
      azurerm_federated_identity_credential.alb.audience == tolist(["api://AzureADTokenExchange"])
    )
    error_message = "tx02v2-lab-alb must trust only azure-alb-system/alb-controller-sa (ALB Controller chart) from the AKS OIDC issuer."
  }

  assert {
    condition = (
      azurerm_federated_identity_credential.otel.user_assigned_identity_id == azurerm_user_assigned_identity.otel.id &&
      azurerm_federated_identity_credential.otel.subject == "system:serviceaccount:observability:opentelemetry-collector" &&
      azurerm_federated_identity_credential.otel.issuer == module.aks.oidc_issuer_url &&
      azurerm_federated_identity_credential.otel.audience == tolist(["api://AzureADTokenExchange"])
    )
    error_message = "tx02v2-lab-otel must trust only observability/opentelemetry-collector from the AKS OIDC issuer (contract v2)."
  }

  assert {
    condition = (
      module.velero.federated_identity_id == module.velero.identity_id &&
      module.velero.federated_subject == "system:serviceaccount:velero:velero" &&
      module.velero.federated_issuer == module.aks.oidc_issuer_url &&
      module.velero.federated_audiences == tolist(["api://AzureADTokenExchange"])
    )
    error_message = "tx02v2-lab-velero must trust only the velero/velero service account from the AKS OIDC issuer."
  }

  assert {
    condition = (
      module.velero.storage_security.shared_access_key_enabled == false &&
      module.velero.storage_security.anonymous_access == false &&
      module.velero.storage_security.public_network_access == "Enabled" &&
      module.velero.storage_security.network_default_action == "Deny" &&
      length(module.velero.storage_security.network_subnet_ids) == 1 &&
      contains(module.velero.storage_security.network_subnet_ids, module.network.aks_nodes_subnet_id) &&
      module.velero.storage_security.container_access_type == "private" &&
      module.velero.storage_security.backup_expiration_days == 35 &&
      azurerm_role_assignment.lab["velero-blob-data-contributor"].scope == module.velero.container_id
    )
    error_message = "Velero uses private keyless Blob storage with 35-day expiry and a container-only data role."
  }

  assert {
    condition     = [azurerm_user_assigned_identity.aks.name, azurerm_user_assigned_identity.kubelet.name, azurerm_user_assigned_identity.eso.name, azurerm_user_assigned_identity.alb.name, azurerm_user_assigned_identity.otel.name, module.velero.identity_name] == ["tx02v2-lab-aks", "tx02v2-lab-kubelet", "tx02v2-lab-eso", "tx02v2-lab-alb", "tx02v2-lab-otel", "tx02v2-lab-velero"]
    error_message = "Lab identity names follow the contract."
  }

  assert {
    condition     = output.eso_identity_client_id == "55555555-5555-5555-5555-555555555555" && output.alb_identity_client_id == "66666666-6666-6666-6666-666666666666" && output.otel_identity_client_id == "99999999-9999-9999-9999-999999999999" && module.velero.identity_client_id == "44444444-4444-4444-4444-444444444444"
    error_message = "platform/install.sh needs the client IDs of the controller identities and of the Collector."
  }

  assert {
    condition = alltrue([
      for t in [azurerm_user_assigned_identity.aks.tags, azurerm_user_assigned_identity.kubelet.tags, azurerm_user_assigned_identity.eso.tags, azurerm_user_assigned_identity.alb.tags, azurerm_user_assigned_identity.otel.tags, module.velero.identity_tags] :
      t == tomap({ Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" })
    ])
    error_message = "Lab identities carry the contract tags."
  }
}

# Contract v2: the traces of the app go to an Application Insights resource that accepts only
# Microsoft Entra ID ingestion (the Collector's Workload ID token), with capped daily ingestion.
run "traces_accept_only_entra_id_ingestion" {
  command = apply

  assert {
    condition = (
      azurerm_application_insights.traces.name == "tx02v2-lab-traces" &&
      azurerm_application_insights.traces.local_authentication_enabled == false &&
      azurerm_application_insights.traces.workspace_id == azurerm_log_analytics_workspace.traces.id &&
      azurerm_application_insights.traces.daily_data_cap_in_gb == 0.5
    )
    error_message = "Application Insights tx02v2-lab-traces: workspace-based, local authentication off, 0.5 GB per day by default."
  }

  assert {
    condition = (
      azurerm_log_analytics_workspace.traces.name == "tx02v2-lab-traces" &&
      azurerm_log_analytics_workspace.traces.local_authentication_enabled == false &&
      azurerm_log_analytics_workspace.traces.sku == "PerGB2018" &&
      azurerm_log_analytics_workspace.traces.retention_in_days == 30 &&
      azurerm_log_analytics_workspace.traces.daily_quota_gb == 0.5
    )
    error_message = "The traces workspace: PerGB2018, local authentication off, 30 days, 0.5 GB per day by default."
  }

  assert {
    condition = alltrue([
      for t in [azurerm_application_insights.traces.tags, azurerm_log_analytics_workspace.traces.tags] :
      t == tomap({ Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" })
    ])
    error_message = "The tracing resources carry the contract tags."
  }

  assert {
    condition     = output.traces_application_insights_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Insights/components/tx02v2-lab-traces"
    error_message = "platform/install.sh finds the traces resource by name (tx02v2-lab-traces)."
  }
}
