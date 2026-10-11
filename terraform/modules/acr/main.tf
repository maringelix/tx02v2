# Azure Container Registry (Basic) for the dx02v2 images. Admin user and anonymous pull are off:
# only Entra ID identities with AcrPull/AcrPush (terraform/envs/lab/roles.tf) can use it.
# Basic has no repository-wide tag immutability, private endpoints or network rules: the dx02v2
# deploy refuses to overwrite an existing tag (contract).

resource "azurerm_container_registry" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Basic"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = false
  tags                          = var.tags
}
