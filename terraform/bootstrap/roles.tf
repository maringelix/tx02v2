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

  # The plan identity runs on pull requests, in a public repository, and its output goes to a public
  # job summary: it reads no data plane. `terraform plan -refresh=false` (the workflow) needs only the
  # management plane (Reader, for the data sources) and the state. A refresh would read the Key Vault
  # secret values, the App Configuration keys and the AKS credentials (docs/ARCHITECTURE.md, ADR 14).
  plan_roles = {
    "reader"            = { scope = local.lab_scope, role = "Reader" }
    "state-blob-reader" = { scope = local.state_scope, role = "Storage Blob Data Reader" }
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
