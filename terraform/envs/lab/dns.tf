# Optional, lab-owned public DNS. The fork owner delegates the zone at the registrar before running
# the full platform installer. Terraform owns only this zone and the app CNAME in the lab resource
# group; no registrar account, domain purchase or real hostname is embedded in this repository.
locals {
  dns_enabled = var.app_domain_name != ""
  dns_label   = local.dns_enabled ? trimsuffix(var.app_domain_name, ".${var.dns_zone_name}") : ""
}

resource "azurerm_dns_zone" "app" {
  count = local.dns_enabled ? 1 : 0

  name                = var.dns_zone_name
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_dns_cname_record" "app" {
  count = local.dns_enabled ? 1 : 0

  name                = local.dns_label
  zone_name           = azurerm_dns_zone.app[0].name
  resource_group_name = data.azurerm_resource_group.lab.name
  ttl                 = 60
  record              = trimsuffix(var.active_region == "secondary" ? module.agc_dr[0].frontend_fqdn : module.agc.frontend_fqdn, ".")
  tags                = local.tags
}
