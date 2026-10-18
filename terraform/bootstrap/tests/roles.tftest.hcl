# Roles of the GitHub identities: scopes, least privilege and the ABAC condition of the apply
# identity (it may only assign the roles of modules/role-ids, the same list the lab root uses;
# terraform/envs/lab/tests/roles.tftest.hcl proves the other side).

mock_provider "azurerm" {
  source = "../tests/mocks"
}

variables {
  github_owner         = "maringelix"
  github_owner_id      = "1000000"
  tx02v2_repository_id = "2000000"
  dx02v2_repository_id = "3000000"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  budget_alert_emails  = ["lab-alerts@example.org"]
}

override_resource {
  target = azurerm_resource_group.bootstrap
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap"
  }
}

# override_resource replaces the mock defaults of the target, so every computed value the
# configuration consumes is set here.
override_resource {
  target = azurerm_user_assigned_identity.plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-gha-plan"
    principal_id = "11111111-1111-1111-1111-111111111111"
    client_id    = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.apply
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-gha-apply"
    principal_id = "22222222-2222-2222-2222-222222222222"
    client_id    = "55555555-5555-5555-5555-555555555555"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.deploy
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dx02v2-gha-deploy"
    principal_id = "33333333-3333-3333-3333-333333333333"
    client_id    = "66666666-6666-6666-6666-666666666666"
  }
}

run "plan_identity_is_read_only" {
  command = apply

  assert {
    condition = { for k, r in azurerm_role_assignment.plan : k => "${r.role_definition_name}@${r.scope}" } == {
      "reader"            = "Reader@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
      "state-blob-reader" = "Storage Blob Data Reader@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.Storage/storageAccounts/tx02v2tfstateb602d594/blobServices/default/containers/tfstate"
    }
    error_message = "tx02v2-gha-plan gets Reader on the lab and the state blob, nothing else: no data plane (docs/ARCHITECTURE.md, ADR 14)."
  }

  assert {
    condition = alltrue([
      for r in azurerm_role_assignment.plan :
      !contains(["Key Vault Secrets User", "Key Vault Secrets Officer", "Key Vault Administrator", "App Configuration Data Reader", "App Configuration Data Owner", "Azure Kubernetes Service Cluster User Role"], r.role_definition_name)
    ])
    error_message = "tx02v2-gha-plan runs on pull requests of a public repository: it reads no secret value, no App Configuration key and no AKS credential."
  }

  assert {
    condition     = alltrue([for r in azurerm_role_assignment.plan : r.principal_id == "11111111-1111-1111-1111-111111111111" && r.principal_type == "ServicePrincipal"])
    error_message = "Plan roles must go to tx02v2-gha-plan."
  }

}

run "apply_identity_is_scoped_to_the_lab" {
  command = apply

  assert {
    condition = { for k, r in azurerm_role_assignment.apply : k => "${r.role_definition_name}@${r.scope}" } == {
      "contributor"              = "Contributor@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
      "keyvault-secrets-officer" = "Key Vault Secrets Officer@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
      "appconfig-data-owner"     = "App Configuration Data Owner@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
      "state-blob-contributor"   = "Storage Blob Data Contributor@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.Storage/storageAccounts/tx02v2tfstateb602d594/blobServices/default/containers/tfstate"
    }
    error_message = "tx02v2-gha-apply gets exactly Contributor, the two data-plane owner roles on the lab and blob access to the state."
  }

  assert {
    condition = (
      azurerm_role_assignment.apply_rbac_administrator.role_definition_name == "Role Based Access Control Administrator" &&
      azurerm_role_assignment.apply_rbac_administrator.scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab" &&
      azurerm_role_assignment.apply_rbac_administrator.principal_id == "22222222-2222-2222-2222-222222222222" &&
      azurerm_role_assignment.apply_rbac_administrator.condition_version == "2.0"
    )
    error_message = "tx02v2-gha-apply manages role assignments only in tx02v2-lab, with an ABAC condition (version 2.0)."
  }

  assert {
    condition = azurerm_role_assignment.apply_rbac_administrator.condition == format(
      "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s}))",
      join(", ", sort(values(module.roles.lab_assignable))),
      join(", ", sort(values(module.roles.lab_assignable))),
    )
    error_message = "The ABAC condition must follow the official constrain-roles template with the lab role list."
  }

  assert {
    # Both the write and the delete branch list exactly the GUIDs of modules/role-ids.
    condition = [
      for m in regexall("GuidEquals \\{([^}]*)\\}", azurerm_role_assignment.apply_rbac_administrator.condition) : toset(split(", ", m[0]))
    ] == [toset(values(module.roles.lab_assignable)), toset(values(module.roles.lab_assignable))]
    error_message = "The role list in the ABAC condition must equal the roles assigned by the lab root."
  }

  assert {
    condition = alltrue([
      for forbidden in [
        "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # Owner
        "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # User Access Administrator
        "b24988ac-6180-42a0-ab88-20f7382dd24c", # Contributor
        "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # Role Based Access Control Administrator
      ] : !strcontains(azurerm_role_assignment.apply_rbac_administrator.condition, forbidden)
    ])
    error_message = "The apply identity must never be able to grant Owner, User Access Administrator, Contributor or RBAC Administrator."
  }
}

run "nothing_at_subscription_scope_and_nothing_for_the_deployer" {
  command = apply

  assert {
    condition = alltrue([
      for r in concat(values(azurerm_role_assignment.plan), values(azurerm_role_assignment.apply), [
        azurerm_role_assignment.apply_rbac_administrator,
        azurerm_role_assignment.state_operator,
      ]) : startswith(r.scope, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/")
    ])
    error_message = "No bootstrap role assignment may be at subscription scope."
  }

  assert {
    condition = alltrue([
      for r in concat(values(azurerm_role_assignment.plan), values(azurerm_role_assignment.apply), [azurerm_role_assignment.apply_rbac_administrator]) :
      r.principal_id != "33333333-3333-3333-3333-333333333333"
    ])
    error_message = "dx02v2-gha-deploy gets its roles from the lab root, on lab resources only (contract)."
  }

  assert {
    condition = alltrue([
      for r in concat(values(azurerm_role_assignment.plan), values(azurerm_role_assignment.apply), [azurerm_role_assignment.apply_rbac_administrator, azurerm_role_assignment.state_operator]) :
      !contains(["Owner", "User Access Administrator"], r.role_definition_name)
    ])
    error_message = "No identity of the lab gets Owner or User Access Administrator."
  }
}
