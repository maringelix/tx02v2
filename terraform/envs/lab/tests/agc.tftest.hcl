# modules/agc tested directly (WAF on and off) and the root wiring of enable_waf.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner        = "maringelix"
  name                = "tx02v2-lab"
  location            = "eastus2"
  resource_group_name = "tx02v2-lab"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/agc"
  enable_waf          = true
  tags                = { Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" }

  # Root inputs for the last run.
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111"]
}

run "agc_with_waf" {
  command = apply

  module {
    source = "../../modules/agc"
  }

  assert {
    condition = (
      azurerm_application_load_balancer.this.name == "tx02v2-lab-agc" &&
      azurerm_application_load_balancer_frontend.this.name == "tx02v2-lab-frontend" &&
      azurerm_application_load_balancer_frontend.this.application_load_balancer_id == azurerm_application_load_balancer.this.id
    )
    error_message = "AGC tx02v2-lab-agc with the frontend tx02v2-lab-frontend (bring-your-own: Terraform owns them)."
  }

  assert {
    condition = (
      azurerm_application_load_balancer_subnet_association.this.subnet_id == var.subnet_id &&
      azurerm_application_load_balancer_subnet_association.this.application_load_balancer_id == azurerm_application_load_balancer.this.id
    )
    error_message = "The association must use the delegated AGC subnet."
  }

  assert {
    condition = (
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].enabled &&
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].mode == "Prevention" &&
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].request_body_check &&
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].request_body_enforcement &&
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].max_request_body_size_in_kb == 128 &&
      azurerm_web_application_firewall_policy.this[0].policy_settings[0].request_body_inspect_limit_in_kb == 128
    )
    error_message = "WAF in Prevention mode with request body inspection and a 128 KB limit (contract: the API answers 413 itself)."
  }

  assert {
    condition = toset([for s in azurerm_web_application_firewall_policy.this[0].managed_rules[0].managed_rule_set : "${s.type}/${s.version}"]) == toset([
      "Microsoft_DefaultRuleSet/2.1",
      "Microsoft_BotManagerRuleSet/1.1",
    ])
    error_message = "Managed rules must be DRS 2.1 (the only core rule set AGC supports) and Bot Manager 1.1."
  }

  assert {
    condition     = length(azurerm_web_application_firewall_policy.this[0].custom_rules) == 0
    error_message = "No custom rule may block the smoke test (contract)."
  }

  assert {
    condition = (
      azurerm_application_load_balancer_security_policy.waf[0].application_load_balancer_id == azurerm_application_load_balancer.this.id &&
      azurerm_application_load_balancer_security_policy.waf[0].web_application_firewall_policy_id == azurerm_web_application_firewall_policy.this[0].id &&
      azurerm_application_load_balancer_security_policy.waf[0].location == "eastus2"
    )
    error_message = "The AGC SecurityPolicy must scope the WAF policy of the lab (same region)."
  }

  assert {
    condition     = output.waf_policy_id == azurerm_web_application_firewall_policy.this[0].id
    error_message = "waf_policy_id must be the WAF policy ID (contract key waf/policy-id)."
  }

  assert {
    condition = alltrue([
      for t in [
        azurerm_application_load_balancer.this.tags,
        azurerm_application_load_balancer_frontend.this.tags,
        azurerm_application_load_balancer_subnet_association.this.tags,
        azurerm_web_application_firewall_policy.this[0].tags,
        azurerm_application_load_balancer_security_policy.waf[0].tags,
      ] : t == var.tags
    ])
    error_message = "Every AGC resource carries the contract tags."
  }
}

run "agc_without_waf" {
  command = plan

  module {
    source = "../../modules/agc"
  }

  variables {
    enable_waf = false
  }

  assert {
    condition     = length(azurerm_web_application_firewall_policy.this) == 0 && length(azurerm_application_load_balancer_security_policy.waf) == 0
    error_message = "enable_waf = false must create neither the WAF policy nor the SecurityPolicy."
  }

  assert {
    condition     = output.waf_policy_id == "none"
    error_message = "Without WAF the contract value of waf/policy-id is the literal none."
  }
}

run "root_publishes_none_without_waf" {
  command = plan

  variables {
    enable_waf = false
  }

  assert {
    condition     = local.contract_keys["waf/policy-id"] == "none" && output.waf_policy_id == "none"
    error_message = "With enable_waf = false the lab must publish waf/policy-id = none."
  }
}

run "root_defaults_to_waf_on" {
  command = apply

  assert {
    condition     = module.agc.waf_policy_id != "none"
    error_message = "WAF must be on by default (parity with tx01v2)."
  }
}
