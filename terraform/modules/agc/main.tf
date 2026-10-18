# Application Gateway for Containers in the "bring your own" deployment mode: Terraform owns the
# Azure resources (AGC, frontend, subnet association, WAF policy and its SecurityPolicy) and the
# ALB Controller only programs them from the Gateway API objects of dx02v2. Destroying the lab
# removes them with Terraform; nothing is created by the controller (docs/ARCHITECTURE.md).

resource "azurerm_application_load_balancer" "this" {
  name                = "${var.name}-agc"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_application_load_balancer_frontend" "this" {
  name                         = "${var.name}-frontend"
  application_load_balancer_id = azurerm_application_load_balancer.this.id
  tags                         = var.tags
}

# The association is the most expensive AGC component (US$0.12/h, US$0.216/h with WAF).
resource "azurerm_application_load_balancer_subnet_association" "this" {
  name                         = "${var.name}-association"
  application_load_balancer_id = azurerm_application_load_balancer.this.id
  subnet_id                    = var.subnet_id
  tags                         = var.tags
}

# --- WAF (enable_waf, on by default) ---

# Contract: Prevention, managed rules DRS 2.1 (the only core set AGC supports) + Bot Manager 1.1,
# request body inspection with a 128 KB limit (the API itself answers 413 for the 70 KB smoke body).
resource "azurerm_web_application_firewall_policy" "this" {
  count = var.enable_waf ? 1 : 0

  name                = "${var.name}-waf"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                          = true
    mode                             = "Prevention"
    request_body_check               = true
    request_body_enforcement         = true
    max_request_body_size_in_kb      = 128
    request_body_inspect_limit_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }
  }
}

# The SecurityPolicy scopes which WAF policy the ALB Controller may reference from a
# WebApplicationFirewallPolicy object (same subscription and region as the AGC).
resource "azurerm_application_load_balancer_security_policy" "waf" {
  count = var.enable_waf ? 1 : 0

  name                               = "${var.name}-waf"
  location                           = var.location
  application_load_balancer_id       = azurerm_application_load_balancer.this.id
  web_application_firewall_policy_id = azurerm_web_application_firewall_policy.this[0].id
  tags                               = var.tags
}
