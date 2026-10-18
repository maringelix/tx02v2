# The three GitHub Actions identities of the contract (docs/CONTRACT.md): user-assigned managed
# identities (no app registration, no client secret, no Entra directory permission needed) with
# one federated credential per exact subject. Issuer and audience are the GitHub defaults.
#
# The subject is the immutable one of GitHub, used by every repository created after 2026-07-15 and
# by the ones that opted in: repo:<owner>@<owner id>/<repository>@<repository id>:<context>. The
# name-based subject (repo:<owner>/<repository>:<context>) is not trusted: it does not match those
# repositories, and whoever registers a deleted account name again would inherit it. A repository
# that predates 2026-07-15 must opt in to immutable subject claims (docs/RUNBOOK.md, section 2);
# scripts/repo-guardrails.sh checks it. Only the apply and deploy jobs use the environment lab,
# whose deployment branches are limited to main (repo-guardrails.sh).
# Azure rejects concurrent writes of federated credentials under the same identity, so the two
# credentials of tx02v2-gha-plan are created one after the other.

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]

  tx_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/tx02v2@${var.tx02v2_repository_id}"
  dx_subject_prefix = "repo:${var.github_owner}@${var.github_owner_id}/dx02v2@${var.dx02v2_repository_id}"

  github_subjects = {
    plan_pull_request = "${local.tx_subject_prefix}:pull_request"
    plan_main         = "${local.tx_subject_prefix}:ref:refs/heads/main"
    apply_lab         = "${local.tx_subject_prefix}:environment:lab"
    deploy_lab        = "${local.dx_subject_prefix}:environment:lab"
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
