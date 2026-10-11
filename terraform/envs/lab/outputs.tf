# Non-sensitive outputs only. Secrets stay in Key Vault (write-only), never in outputs.

output "location" {
  description = "Azure location of the lab."
  value       = var.location
}

output "resource_group_name" {
  description = "Resource group of the lab."
  value       = data.azurerm_resource_group.lab.name
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = module.aks.cluster_name
}

output "node_resource_group" {
  description = "Node resource group created and owned by AKS."
  value       = module.aks.node_resource_group
}

output "get_credentials_command" {
  description = "Writes a kubeconfig entry for the cluster and converts it to Azure CLI tokens (local accounts are disabled; needs kubelogin)."
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.lab.name} --name ${module.aks.cluster_name} --overwrite-existing && kubelogin convert-kubeconfig -l azurecli"
}

output "appconfig_endpoint" {
  description = "App Configuration endpoint of the contract (dx02v2 GitHub variable AZURE_APPCONFIG_ENDPOINT)."
  value       = module.appconfig.endpoint
}

output "contract_keys" {
  description = "Contract keys written to App Configuration."
  value       = module.appconfig.key_names
}

output "acr_login_server" {
  description = "Login server of the registry."
  value       = module.acr.login_server
}

output "keyvault_uri" {
  description = "URI of the lab Key Vault."
  value       = module.keyvault.uri
}

output "agc_id" {
  description = "Resource ID of the Application Gateway for Containers."
  value       = module.agc.id
}

output "agc_frontend_name" {
  description = "Name of the AGC frontend."
  value       = module.agc.frontend_name
}

output "agc_frontend_fqdn" {
  description = "Public FQDN of the AGC frontend (the app answers there once dx02v2 is deployed)."
  value       = module.agc.frontend_fqdn
}

output "waf_policy_id" {
  description = "WAF policy ID, or none when enable_waf = false."
  value       = module.agc.waf_policy_id
}

output "postgres_fqdn" {
  description = "Private FQDN of PostgreSQL (resolvable only inside the VNet)."
  value       = module.postgres.fqdn
}

output "eso_identity_client_id" {
  description = "Client ID of tx02v2-lab-eso (ServiceAccount annotation of External Secrets)."
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "alb_identity_client_id" {
  description = "Client ID of tx02v2-lab-alb (albController.podIdentity.clientID of the ALB Controller chart)."
  value       = azurerm_user_assigned_identity.alb.client_id
}
