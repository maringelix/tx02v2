# Identifiers only (no secret exists: GitHub reaches Azure through OIDC). They are not secret,
# but they identify your tenant and subscription: keep them out of public issues.

output "tenant_id" {
  description = "Entra ID tenant of the subscription."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Subscription of the lab."
  value       = var.subscription_id
}

output "state_storage_account_name" {
  description = "Storage account of the lab state."
  value       = azurerm_storage_account.state.name
}

output "backend_hcl" {
  description = "Ready content of terraform/envs/lab/backend.hcl (git-ignored)."
  value       = <<-EOT
    storage_account_name = "${azurerm_storage_account.state.name}"
  EOT
}

output "plan_client_id" {
  description = "Client ID of tx02v2-gha-plan (tx02v2 variable AZURE_PLAN_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.plan.client_id
}

output "apply_client_id" {
  description = "Client ID of tx02v2-gha-apply (tx02v2 variable AZURE_APPLY_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.apply.client_id
}

output "apply_principal_id" {
  description = "Object ID of tx02v2-gha-apply: put it in cluster_admin_principal_ids (platform and destroy workflows)."
  value       = azurerm_user_assigned_identity.apply.principal_id
}

output "deploy_client_id" {
  description = "Client ID of dx02v2-gha-deploy (dx02v2 variable AZURE_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.deploy.client_id
}

output "deploy_principal_id" {
  description = "Object ID of dx02v2-gha-deploy (tx02v2 variable LAB_DEPLOY_PRINCIPAL_ID)."
  value       = azurerm_user_assigned_identity.deploy.principal_id
}

output "appconfig_endpoint" {
  description = "Endpoint the lab root will give the contract store (dx02v2 variable AZURE_APPCONFIG_ENDPOINT)."
  value       = local.appconfig_endpoint
}

output "budget_name" {
  description = "Cost Management budget that sends the alerts."
  value       = azurerm_consumption_budget_subscription.monthly.name
}

output "github_variables_tx02v2" {
  description = "Repository variables of tx02v2 known after the bootstrap (docs/RUNBOOK.md lists the LAB_* ones you choose)."
  value = {
    AZURE_TENANT_ID          = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID    = var.subscription_id
    AZURE_PLAN_CLIENT_ID     = azurerm_user_assigned_identity.plan.client_id
    AZURE_APPLY_CLIENT_ID    = azurerm_user_assigned_identity.apply.client_id
    TF_STATE_STORAGE_ACCOUNT = azurerm_storage_account.state.name
    LAB_LOCATION             = var.location
    LAB_DEPLOY_PRINCIPAL_ID  = azurerm_user_assigned_identity.deploy.principal_id
  }
}

# The lists that name the people who operate the lab are secrets, not variables: the logs, the job
# summary and the artifacts of a public repository are public, and a secret is masked (the workflows
# also mask each element). Add your own object ID to LAB_CLUSTER_ADMIN_PRINCIPAL_IDS and the address
# you operate from to LAB_API_SERVER_AUTHORIZED_IP_RANGES (docs/RUNBOOK.md, section 3).
output "github_secrets_tx02v2" {
  description = "Repository secrets of tx02v2 known after the bootstrap (gh secret set -f; docs/RUNBOOK.md, section 3)."
  sensitive   = true
  value = {
    LAB_CLUSTER_ADMIN_PRINCIPAL_IDS = jsonencode([azurerm_user_assigned_identity.apply.principal_id])
  }
}

output "github_variables_dx02v2" {
  description = "Repository variables of dx02v2 (its deploy workflow)."
  value = {
    AZURE_CLIENT_ID          = azurerm_user_assigned_identity.deploy.client_id
    AZURE_TENANT_ID          = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID    = var.subscription_id
    AZURE_APPCONFIG_ENDPOINT = local.appconfig_endpoint
  }
}
