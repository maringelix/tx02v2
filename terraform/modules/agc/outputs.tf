output "id" {
  description = "Resource ID of the Application Gateway for Containers (contract key agc/id)."
  value       = azurerm_application_load_balancer.this.id
}

output "frontend_name" {
  description = "Name of the AGC frontend (contract key agc/frontend-name)."
  value       = azurerm_application_load_balancer_frontend.this.name
}

output "frontend_fqdn" {
  description = "Public FQDN of the frontend (the Gateway address)."
  value       = azurerm_application_load_balancer_frontend.this.fully_qualified_domain_name
}

output "waf_policy_id" {
  description = "WAF policy ID, or the literal none when enable_waf = false (contract key waf/policy-id)."
  value       = var.enable_waf ? azurerm_web_application_firewall_policy.this[0].id : "none"
}
