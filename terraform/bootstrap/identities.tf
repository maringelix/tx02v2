# The three GitHub Actions identities of the contract (docs/CONTRATO.md): user-assigned managed
# identities (no app registration, no client secret, no Entra directory permission needed) with
# one federated credential per exact subject. Issuer and audience are the GitHub defaults.
# Azure rejects concurrent writes of federated credentials under the same identity, so the two
# credentials of tx02v2-gha-plan are created one after the other.

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]

  github_subjects = {
    plan_pull_request = "repo:${var.github_owner}/tx02v2:pull_request"
    plan_main         = "repo:${var.github_owner}/tx02v2:ref:refs/heads/main"
    apply_lab         = "repo:${var.github_owner}/tx02v2:environment:lab"
    deploy_lab        = "repo:${var.github_owner}/dx02v2:environment:lab"
  }
}

resource "azurerm_user_assigned_identity" "plan" {
  name                = "tx02v2-gha-plan"
  location            = var.location
  resource_group_name = azurerm_resource_group.bootstrap.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "apply" {
  name                = "tx02v2-gha-apply"
  location            = var.location
  resource_group_name = azurerm_resource_group.bootstrap.name
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "deploy" {
  name                = "dx02v2-gha-deploy"
  location            = var.location
  resource_group_name = azurerm_resource_group.bootstrap.name
  tags                = local.tags
}

# tx02v2-gha-plan: pull requests and main of tx02v2, never an environment.
resource "azurerm_federated_identity_credential" "plan_pull_request" {
  name                      = "github-tx02v2-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = local.github_subjects.plan_pull_request
}

resource "azurerm_federated_identity_credential" "plan_main" {
  name                      = "github-tx02v2-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = local.github_subjects.plan_main

  depends_on = [azurerm_federated_identity_credential.plan_pull_request]
}

# tx02v2-gha-apply: only jobs of tx02v2 that run in the protected environment lab.
resource "azurerm_federated_identity_credential" "apply_lab" {
  name                      = "github-tx02v2-environment-lab"
  user_assigned_identity_id = azurerm_user_assigned_identity.apply.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = local.github_subjects.apply_lab
}

# dx02v2-gha-deploy: only jobs of dx02v2 that run in its environment lab.
resource "azurerm_federated_identity_credential" "deploy_lab" {
  name                      = "github-dx02v2-environment-lab"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = local.github_subjects.deploy_lab
}
