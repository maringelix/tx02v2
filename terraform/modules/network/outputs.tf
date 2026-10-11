output "vnet_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name."
  value       = azurerm_virtual_network.this.name
}

output "vnet_cidr" {
  description = "VNet address space (contract key vnet-cidr)."
  value       = var.vnet_cidr
}

output "aks_nodes_subnet_id" {
  description = "Subnet of the AKS nodes."
  value       = azurerm_subnet.aks_nodes.id
}

output "agc_subnet_id" {
  description = "Subnet delegated to Application Gateway for Containers."
  value       = azurerm_subnet.agc.id
}

output "agc_subnet_cidr" {
  description = "CIDR of the AGC subnet (contract key agc-subnet-cidr)."
  value       = var.agc_subnet_cidr
}

output "postgres_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server."
  value       = azurerm_subnet.postgres.id
}

output "postgres_subnet_cidr" {
  description = "CIDR of the PostgreSQL subnet (contract key postgres-subnet-cidr)."
  value       = var.postgres_subnet_cidr
}

output "postgres_private_dns_zone_id" {
  description = "Private DNS zone of the Flexible Server."
  value       = azurerm_private_dns_zone.postgres.id
}

output "postgres_private_dns_zone_link_id" {
  description = "VNet link of the private DNS zone (the server depends on it)."
  value       = azurerm_private_dns_zone_virtual_network_link.postgres.id
}

output "postgres_subnet_nsg_association_id" {
  description = "NSG association of the PostgreSQL subnet (the server waits for it)."
  value       = azurerm_subnet_network_security_group_association.postgres.id
}
