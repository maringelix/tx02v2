# GitHub OIDC identities and their federated credentials (docs/CONTRATO.md, contract v1).

mock_provider "azurerm" {
  source = "../tests/mocks"
}

variables {
  github_owner        = "maringelix"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  budget_alert_emails = ["lab-alerts@example.org"]
}

override_resource {
  target = azurerm_user_assigned_identity.plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-gha-plan"
    principal_id = "11111111-1111-1111-1111-111111111111"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.apply
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-gha-apply"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.deploy
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dx02v2-gha-deploy"
    principal_id = "33333333-3333-3333-3333-333333333333"
  }
}

run "identities_follow_the_contract" {
  command = apply

  assert {
    condition     = [azurerm_user_assigned_identity.plan.name, azurerm_user_assigned_identity.apply.name, azurerm_user_assigned_identity.deploy.name] == ["tx02v2-gha-plan", "tx02v2-gha-apply", "dx02v2-gha-deploy"]
    error_message = "Identity names must follow the contract."
  }

  assert {
    condition = alltrue([
      for i in [azurerm_user_assigned_identity.plan, azurerm_user_assigned_identity.apply, azurerm_user_assigned_identity.deploy] :
      i.resource_group_name == "tx02v2-bootstrap" && i.location == "eastus2"
    ])
    error_message = "The GitHub identities live in tx02v2-bootstrap (they survive the lab destroys)."
  }

  assert {
    condition = [
      for fc in [azurerm_federated_identity_credential.plan_pull_request, azurerm_federated_identity_credential.plan_main] : fc.subject
      if fc.user_assigned_identity_id == azurerm_user_assigned_identity.plan.id
      ] == [
      "repo:maringelix/tx02v2:pull_request",
      "repo:maringelix/tx02v2:ref:refs/heads/main",
    ]
    error_message = "tx02v2-gha-plan must trust exactly the tx02v2 pull_request and main subjects."
  }

  assert {
    condition = alltrue([
      for fc in [azurerm_federated_identity_credential.plan_pull_request, azurerm_federated_identity_credential.plan_main] : !strcontains(fc.subject, ":environment:")
    ])
    error_message = "tx02v2-gha-plan must not trust any environment subject."
  }

  assert {
    condition = (
      azurerm_federated_identity_credential.apply_lab.user_assigned_identity_id == azurerm_user_assigned_identity.apply.id &&
      azurerm_federated_identity_credential.apply_lab.subject == "repo:maringelix/tx02v2:environment:lab"
    )
    error_message = "tx02v2-gha-apply must trust only repo:maringelix/tx02v2:environment:lab."
  }

  assert {
    condition = (
      azurerm_federated_identity_credential.deploy_lab.user_assigned_identity_id == azurerm_user_assigned_identity.deploy.id &&
      azurerm_federated_identity_credential.deploy_lab.subject == "repo:maringelix/dx02v2:environment:lab"
    )
    error_message = "dx02v2-gha-deploy must trust only repo:maringelix/dx02v2:environment:lab."
  }

  assert {
    condition = alltrue([
      for fc in [
        azurerm_federated_identity_credential.plan_pull_request,
        azurerm_federated_identity_credential.plan_main,
        azurerm_federated_identity_credential.apply_lab,
        azurerm_federated_identity_credential.deploy_lab,
      ] :
      fc.issuer == "https://token.actions.githubusercontent.com" && fc.audience == tolist(["api://AzureADTokenExchange"])
    ])
    error_message = "Every federated credential must use the GitHub issuer and the api://AzureADTokenExchange audience."
  }

  assert {
    condition = length(distinct([
      for fc in [
        azurerm_federated_identity_credential.plan_pull_request,
        azurerm_federated_identity_credential.plan_main,
        azurerm_federated_identity_credential.apply_lab,
        azurerm_federated_identity_credential.deploy_lab,
      ] : fc.subject
    ])) == 4
    error_message = "One federated credential per exact subject (no duplicates, no wildcards)."
  }

  assert {
    condition     = output.deploy_principal_id == "33333333-3333-3333-3333-333333333333" && output.apply_principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "The principal IDs needed by the lab root must be outputs."
  }
}

run "github_owner_is_configurable" {
  command = plan

  variables {
    github_owner = "example-org"
  }

  assert {
    condition     = azurerm_federated_identity_credential.apply_lab.subject == "repo:example-org/tx02v2:environment:lab" && azurerm_federated_identity_credential.deploy_lab.subject == "repo:example-org/dx02v2:environment:lab"
    error_message = "The owner in the subjects must follow var.github_owner."
  }

  assert {
    condition     = azurerm_resource_group.bootstrap.tags["Repository"] == "example-org/tx02v2"
    error_message = "The Repository tag must follow var.github_owner."
  }
}

run "rejects_a_bad_github_owner" {
  command = plan

  variables {
    github_owner = "-not-valid-"
  }

  expect_failures = [var.github_owner]
}

run "placeholder_owner_is_refused" {
  command = plan

  variables {
    github_owner = "your-github-user"
  }

  expect_failures = [var.github_owner]
}
