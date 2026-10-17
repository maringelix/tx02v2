# VNet of the lab with three subnets (AKS nodes, Application Gateway for Containers, PostgreSQL),
# an NSG that lets only the AKS node subnet reach PostgreSQL on 5432, and the private DNS zone of
# the Flexible Server linked to the VNet. CIDRs are validated by the calling root.
#
# Not here on purpose (docs/ARQUITETURA.md): NSG flow logs (being retired by Azure) and VNet flow
# logs (they need a Network Watcher in NetworkWatcherRG, outside the lab resource group the CI
# identities are scoped to, plus a storage account); no NSG on the AKS node subnet (AKS manages
# the NSG of the node NICs) or on the AGC subnet (traffic AGC -> pods is filtered by the app
# NetworkPolicies, contract: agc-subnet-cidr).

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_nodes_subnet_cidr]

  service_endpoint {
    service = "Microsoft.Storage"
  }
}

resource "azurerm_subnet" "agc" {
  name                 = "agc"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.agc_subnet_cidr]

  delegation {
    name = "application-gateway-for-containers"

    service_delegation {
      name    = "Microsoft.ServiceNetworking/trafficControllers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgres_subnet_cidr]

  delegation {
    name = "postgresql-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "postgres" {
  name                = "${var.name}-postgres"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "postgres_from_aks_nodes" {
  name                        = "allow-postgres-from-aks-nodes"
  description                 = "PostgreSQL 5432 only from the AKS node subnet (Azure CNI Overlay SNATs pod traffic to the node IP)."
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgres.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = var.aks_nodes_subnet_cidr
  source_port_range           = "*"
  destination_address_prefix  = var.postgres_subnet_cidr
  destination_port_range      = "5432"
}

resource "azurerm_network_security_rule" "postgres_intra_subnet" {
  name                        = "allow-postgres-subnet-internal"
  description                 = "Traffic inside the delegated subnet (Flexible Server management of its own instances)."
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgres.name
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_address_prefix       = var.postgres_subnet_cidr
  source_port_range           = "*"
  destination_address_prefix  = var.postgres_subnet_cidr
  destination_port_range      = "*"
}

resource "azurerm_network_security_rule" "postgres_from_peer" {
  count                       = var.postgres_peer_cidr == "" ? 0 : 1
  name                        = "allow-postgres-from-dr-peer"
  description                 = "Private PostgreSQL replication between the two peered regions; TCP 5432 only."
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgres.name
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefix       = var.postgres_peer_cidr
  source_port_range           = "*"
  destination_address_prefix  = var.postgres_subnet_cidr
  destination_port_range      = "5432"
}

resource "azurerm_network_security_rule" "postgres_deny_other_vnet" {
  name                        = "deny-other-vnet-inbound"
  description                 = "Everything else from the VNet (AGC subnet included) is denied; AzureLoadBalancer probes keep the default rule."
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgres.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_address_prefix       = "VirtualNetwork"
  source_port_range           = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.postgres.id
}

# Private DNS zone of the Flexible Server (private access): its name must end with
# .postgres.database.azure.com. The server registers its A record here.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                 = "${var.name}-vnet"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}
