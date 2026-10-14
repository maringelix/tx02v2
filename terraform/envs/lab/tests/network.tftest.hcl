# modules/network tested directly.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner          = "maringelix"
  name                  = "tx02v2-lab"
  location              = "eastus2"
  resource_group_name   = "tx02v2-lab"
  vnet_cidr             = "10.20.0.0/16"
  aks_nodes_subnet_cidr = "10.20.0.0/22"
  agc_subnet_cidr       = "10.20.4.0/24"
  postgres_subnet_cidr  = "10.20.5.0/24"
  tags                  = { Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2" }
}

override_resource {
  target = azurerm_subnet.postgres
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/postgres" }
}

run "vnet_and_subnets" {
  command = apply

  module {
    source = "../../modules/network"
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "tx02v2-lab-vnet" && azurerm_virtual_network.this.address_space == toset(["10.20.0.0/16"])
    error_message = "The VNet must be tx02v2-lab-vnet with vnet_cidr as its only address space."
  }

  assert {
    condition = (
      azurerm_subnet.aks_nodes.name == "aks-nodes" && azurerm_subnet.aks_nodes.address_prefixes == tolist(["10.20.0.0/22"]) &&
      azurerm_subnet.agc.name == "agc" && azurerm_subnet.agc.address_prefixes == tolist(["10.20.4.0/24"]) &&
      azurerm_subnet.postgres.name == "postgres" && azurerm_subnet.postgres.address_prefixes == tolist(["10.20.5.0/24"])
    )
    error_message = "Subnets aks-nodes, agc and postgres must use the CIDR variables."
  }

  assert {
    condition     = length(azurerm_subnet.aks_nodes.delegation) == 0
    error_message = "The AKS node subnet must not be delegated."
  }

  assert {
    condition     = one(azurerm_subnet.agc.delegation[0].service_delegation).name == "Microsoft.ServiceNetworking/trafficControllers"
    error_message = "The AGC subnet must be delegated to Microsoft.ServiceNetworking/trafficControllers."
  }

  assert {
    condition     = one(azurerm_subnet.postgres.delegation[0].service_delegation).name == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "The PostgreSQL subnet must be delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  }

  assert {
    condition = (
      azurerm_private_dns_zone.postgres.name == "tx02v2-lab.private.postgres.database.azure.com" &&
      azurerm_private_dns_zone_virtual_network_link.postgres.private_dns_zone_id == azurerm_private_dns_zone.postgres.id &&
      azurerm_private_dns_zone_virtual_network_link.postgres.virtual_network_id == azurerm_virtual_network.this.id &&
      azurerm_private_dns_zone_virtual_network_link.postgres.registration_enabled == false
    )
    error_message = "The private DNS zone tx02v2-lab.private.postgres.database.azure.com must be linked to the VNet (no auto-registration)."
  }

  assert {
    condition = alltrue([
      for t in [
        azurerm_virtual_network.this.tags,
        azurerm_network_security_group.postgres.tags,
        azurerm_private_dns_zone.postgres.tags,
        azurerm_private_dns_zone_virtual_network_link.postgres.tags,
      ] : t == var.tags
    ])
    error_message = "Every taggable network resource carries the contract tags."
  }
}

run "postgres_is_reachable_only_from_the_aks_nodes" {
  command = apply

  module {
    source = "../../modules/network"
  }

  assert {
    condition = (
      azurerm_network_security_rule.postgres_from_aks_nodes.direction == "Inbound" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.access == "Allow" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.protocol == "Tcp" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.source_address_prefix == "10.20.0.0/22" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.destination_address_prefix == "10.20.5.0/24" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.destination_port_range == "5432" &&
      azurerm_network_security_rule.postgres_from_aks_nodes.priority == 100
    )
    error_message = "Only TCP 5432 from the AKS node subnet may reach the PostgreSQL subnet."
  }

  assert {
    condition = (
      azurerm_network_security_rule.postgres_deny_other_vnet.access == "Deny" &&
      azurerm_network_security_rule.postgres_deny_other_vnet.direction == "Inbound" &&
      azurerm_network_security_rule.postgres_deny_other_vnet.source_address_prefix == "VirtualNetwork" &&
      azurerm_network_security_rule.postgres_deny_other_vnet.priority > azurerm_network_security_rule.postgres_from_aks_nodes.priority &&
      azurerm_network_security_rule.postgres_deny_other_vnet.priority < 65000
    )
    error_message = "Everything else from the VNet must be denied before the default AllowVnetInBound rule (65000)."
  }

  assert {
    condition = (
      azurerm_network_security_rule.postgres_intra_subnet.source_address_prefix == "10.20.5.0/24" &&
      azurerm_network_security_rule.postgres_intra_subnet.destination_address_prefix == "10.20.5.0/24"
    )
    error_message = "Intra-subnet traffic of the Flexible Server stays allowed."
  }

  assert {
    condition     = azurerm_subnet_network_security_group_association.postgres.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/postgres"
    error_message = "The NSG must be attached to the PostgreSQL subnet."
  }
}

run "cidrs_follow_the_variables" {
  command = plan

  module {
    source = "../../modules/network"
  }

  variables {
    vnet_cidr             = "172.16.0.0/20"
    aks_nodes_subnet_cidr = "172.16.0.0/23"
    agc_subnet_cidr       = "172.16.4.0/24"
    postgres_subnet_cidr  = "172.16.5.0/26"
  }

  assert {
    condition     = azurerm_virtual_network.this.address_space == toset(["172.16.0.0/20"]) && azurerm_subnet.postgres.address_prefixes == tolist(["172.16.5.0/26"])
    error_message = "CIDRs must come from the variables, never hardcoded values."
  }

  assert {
    condition     = azurerm_network_security_rule.postgres_from_aks_nodes.source_address_prefix == "172.16.0.0/23"
    error_message = "The NSG rule must follow aks_nodes_subnet_cidr."
  }
}
