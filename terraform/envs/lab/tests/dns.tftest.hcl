# Public DNS is optional for core; full needs a delegated zone and an ACME contact.
mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner                    = "maringelix"
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111"]
}

run "dns_disabled_by_default" {
  command = plan

  assert {
    condition = (
      length(azurerm_dns_zone.app) == 0 &&
      length(azurerm_dns_cname_record.app) == 0 &&
      local.contract_keys["dns/hostname"] == "disabled" &&
      local.contract_keys["dns/acme-email"] == "disabled" &&
      output.dns_hostname == "disabled"
    )
    error_message = "The core defaults create no public DNS and publish disabled TLS values."
  }
}

run "dns_points_only_to_the_lab_frontend" {
  command = apply

  variables {
    dns_zone_name      = "example.com"
    app_domain_name    = "lab.example.com"
    acme_contact_email = "ops@example.com"
  }

  assert {
    condition = (
      azurerm_dns_zone.app[0].name == "example.com" &&
      azurerm_dns_zone.app[0].resource_group_name == "tx02v2-lab"
    )
    error_message = "The lab owns only its tagged public DNS zone."
  }

  assert {
    condition = (
      azurerm_dns_cname_record.app[0].name == "lab" &&
      azurerm_dns_cname_record.app[0].zone_name == azurerm_dns_zone.app[0].name &&
      azurerm_dns_cname_record.app[0].record == module.agc.frontend_fqdn &&
      azurerm_dns_cname_record.app[0].ttl == 60
    )
    error_message = "The tagged app CNAME must point to the AGC frontend with a short TTL."
  }

  assert {
    condition = (
      output.dns_hostname == "lab.example.com" &&
      local.contract_keys["dns/acme-email"] == "ops@example.com"
    )
    error_message = "The contract must publish the app hostname and ACME contact."
  }
}

run "rejects_a_hostname_outside_its_zone" {
  command = plan

  variables {
    dns_zone_name      = "example.com"
    app_domain_name    = "lab.other.net"
    acme_contact_email = "ops@example.com"
  }

  expect_failures = [var.app_domain_name]
}

run "rejects_a_partial_dns_configuration" {
  command = plan

  variables {
    dns_zone_name   = "example.com"
    app_domain_name = "lab.example.com"
  }

  expect_failures = [var.app_domain_name]
}

run "rejects_an_invalid_contact_email" {
  command = plan

  variables {
    dns_zone_name      = "example.com"
    app_domain_name    = "lab.example.com"
    acme_contact_email = "not-an-email"
  }

  expect_failures = [var.acme_contact_email]
}
