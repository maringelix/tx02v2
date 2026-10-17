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
  description = "Writes the kubeconfig of the cluster to its own file and converts it to Azure CLI tokens (local accounts are disabled; needs kubelogin); ~/.kube/config, its current context and its other users stay untouched. Then: export KUBECONFIG=/tmp/tx02v2-lab.kubeconfig"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.lab.name} --name ${module.aks.cluster_name} --file /tmp/${module.aks.cluster_name}.kubeconfig --overwrite-existing && kubelogin convert-kubeconfig -l azurecli --kubeconfig /tmp/${module.aks.cluster_name}.kubeconfig"
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

output "dns_hostname" {
  description = "Application hostname when public DNS is configured, or disabled. HTTPS needs delegation and a successful ACME challenge."
  value       = local.dns_enabled ? var.app_domain_name : "disabled"
}

output "dns_name_servers" {
  description = "Delegate the optional lab-owned public zone to these Azure DNS name servers before platform/install.sh --profile full."
  value       = local.dns_enabled ? azurerm_dns_zone.app[0].name_servers : []
}

output "waf_policy_id" {
  description = "WAF policy ID, or none when enable_waf = false."
  value       = module.agc.waf_policy_id
}

output "postgres_fqdn" {
  description = "Private FQDN of PostgreSQL (resolvable only inside the VNet)."
  value       = module.postgres.fqdn
}

output "postgres_profile" {
  description = "Selected continuity profile."
  value       = var.postgres_profile
}

output "dr_cluster_name" {
  description = "Secondary AKS cluster name or empty without DR."
  value       = var.postgres_profile == "dr" ? module.aks_dr[0].cluster_name : ""
}

output "dr_appconfig_endpoint" {
  description = "Secondary App Configuration endpoint for the coordinated DX deploy workflow."
  value       = var.postgres_profile == "dr" ? module.appconfig_dr[0].endpoint : ""
}

output "dr_postgres_name" {
  description = "Private cross-region read replica for manually approved promotion."
  value       = var.postgres_profile == "dr" ? azurerm_postgresql_flexible_server.replica[0].name : ""
}

output "dr_location" {
  description = "Secondary Azure region or empty without DR."
  value       = var.postgres_profile == "dr" ? var.dr_location : ""
}

output "eso_identity_client_id" {
  description = "Client ID of tx02v2-lab-eso (ServiceAccount annotation of External Secrets)."
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "alb_identity_client_id" {
  description = "Client ID of tx02v2-lab-alb (albController.podIdentity.clientID of the ALB Controller chart)."
  value       = azurerm_user_assigned_identity.alb.client_id
}
output "otel_identity_client_id" {
  description = "Client ID of tx02v2-lab-otel (ServiceAccount annotation of the OpenTelemetry Collector)."
  value       = azurerm_user_assigned_identity.otel.client_id
}

output "traces_application_insights_id" {
  description = "Application Insights resource that receives the traces of the app (contract v2)."
  value       = azurerm_application_insights.traces.id
}
