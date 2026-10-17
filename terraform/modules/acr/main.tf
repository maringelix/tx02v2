# Azure Container Registry (Standard) for the dx02v2 images. ABAC repository permissions are only
# supported on Standard/Premium: identities receive access to dx02v2/api and dx02v2/web separately
# (terraform/envs/lab/roles.tf). Admin user and anonymous pull are off. The dx02v2 deploy refuses to
# overwrite an existing tag (contract).

resource "azurerm_container_registry" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Standard"
  role_assignment_mode          = "AbacRepositoryPermissions"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = false
  tags                          = var.tags
}
