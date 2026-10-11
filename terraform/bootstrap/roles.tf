# Azure roles of the GitHub identities. Every scope is the tx02v2-lab resource group, a resource
# inside it, or the state container: nothing at subscription scope. dx02v2-gha-deploy gets its
# roles from the lab root, on the lab resources (contract).

locals {
  lab_scope   = azurerm_resource_group.lab.id
  state_scope = azurerm_storage_container.state.id

  # The only roles tx02v2-gha-apply may assign or remove (ABAC condition of its Role Based Access
  # Control Administrator assignment). Same list the lab root uses: modules/role-ids.
  apply_assignable_role_ids = sort(values(module.roles.lab_assignable))

  # Syntax of the official "Constrain roles" example (learn.microsoft.com, Azure RBAC:
  # delegate role assignment management with conditions; verified 2026-10-11).
  apply_role_assignment_condition = format(
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s}))",
    join(", ", local.apply_assignable_role_ids),
    join(", ", local.apply_assignable_role_ids),
  )

  # What a `terraform plan -refresh` of the lab really calls besides Reader (azurerm 5.9.0 source,
  # docs/ARQUITETURA.md): AKS ListClusterUserCredentials, Key Vault GetSecret (it returns the
  # value), App Configuration GetKeyValue and the store ListKeys. Least privileged roles for each.
  plan_roles = {
    "reader"                = { scope = local.lab_scope, role = "Reader" }
    "aks-cluster-user"      = { scope = local.lab_scope, role = "Azure Kubernetes Service Cluster User Role" }
    "keyvault-secrets-user" = { scope = local.lab_scope, role = "Key Vault Secrets User" }
    "appconfig-data-reader" = { scope = local.lab_scope, role = "App Configuration Data Reader" }
    "state-blob-reader"     = { scope = local.state_scope, role = "Storage Blob Data Reader" }
  }

  apply_roles = {
    "contributor"              = { scope = local.lab_scope, role = "Contributor" }
    "keyvault-secrets-officer" = { scope = local.lab_scope, role = "Key Vault Secrets Officer" }
    "appconfig-data-owner"     = { scope = local.lab_scope, role = "App Configuration Data Owner" }
    "state-blob-contributor"   = { scope = local.state_scope, role = "Storage Blob Data Contributor" }
  }
}

# --- tx02v2-gha-plan: read-only, plans run with -lock=false ---

resource "azurerm_role_assignment" "plan" {
  for_each = local.plan_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
  description          = "tx02v2-gha-plan: ${each.key}"
}

# The refresh of azurerm_app_configuration lists the access keys and fails without this action;
# no built-in read role has it. The keys are useless anyway: local auth is disabled on the store.
resource "azurerm_role_definition" "plan_appconfig_list_keys" {
  name        = "tx02v2-plan-appconfig-listkeys-${local.suffix}"
  scope       = local.lab_scope
  description = "tx02v2-gha-plan: list the (disabled) access keys of App Configuration stores, needed by the azurerm refresh."

  permissions {
    actions = ["Microsoft.AppConfiguration/configurationStores/ListKeys/action"]
  }

  assignable_scopes = [local.lab_scope]
}

resource "azurerm_role_assignment" "plan_appconfig_list_keys" {
  scope              = local.lab_scope
  role_definition_id = azurerm_role_definition.plan_appconfig_list_keys.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.plan.principal_id
  principal_type     = "ServicePrincipal"
  description        = "tx02v2-gha-plan: appconfig-list-keys"
}

# --- tx02v2-gha-apply: environment lab only (required reviewer) ---

resource "azurerm_role_assignment" "apply" {
  for_each = local.apply_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  description          = "tx02v2-gha-apply: ${each.key}"
}

# Role assignments inside the lab resource group, limited by ABAC to the roles of
# modules/role-ids (never Owner, User Access Administrator or Contributor).
resource "azurerm_role_assignment" "apply_rbac_administrator" {
  scope                = local.lab_scope
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  condition            = local.apply_role_assignment_condition
  condition_version    = "2.0"
  description          = "tx02v2-gha-apply: assign only the lab roles (ABAC)"
}
