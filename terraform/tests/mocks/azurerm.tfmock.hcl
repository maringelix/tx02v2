# Shared mock data for `terraform test` (mock_provider "azurerm" { source = ".../tests/mocks" }).
# No Azure API is ever contacted. Identifiers use the zero subscription/tenant GUID and obviously
# fake GUIDs. Resource IDs must be well formed: the real provider schema still validates
# arguments such as subnet, vault or identity IDs once mocked values become known during apply.
# Every instance of a type gets the same default: tests that compare IDs use override_resource
# to give the instances under test distinct values.

mock_data "azurerm_client_config" {
  defaults = {
    client_id       = "00000000-0000-0000-0000-000000000000"
    object_id       = "99999999-9999-9999-9999-999999999999"
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}

mock_data "azurerm_resource_group" {
  defaults = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
    location = "eastus2"
    tags     = {}
  }
}

mock_resource "azurerm_resource_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
  }
}

mock_resource "azurerm_user_assigned_identity" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock"
    principal_id = "33333333-3333-3333-3333-333333333333"
    client_id    = "44444444-4444-4444-4444-444444444444"
    tenant_id    = "00000000-0000-0000-0000-000000000000"
  }
}

mock_resource "azurerm_federated_identity_credential" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock/federatedIdentityCredentials/mock"
  }
}

mock_resource "azurerm_role_assignment" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/88888888-8888-8888-8888-888888888888"
  }
}

mock_resource "azurerm_role_definition" {
  defaults = {
    id                          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa|/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab"
    role_definition_id          = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  }
}

mock_resource "azurerm_storage_account" {
  defaults = {
    id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.Storage/storageAccounts/tx02v2tfstateb602d594"
    primary_blob_endpoint = "https://tx02v2tfstateb602d594.blob.core.windows.net/"
  }
}

mock_resource "azurerm_storage_container" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.Storage/storageAccounts/tx02v2tfstateb602d594/blobServices/default/containers/tfstate"
  }
}

mock_resource "azurerm_management_lock" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap/providers/Microsoft.Storage/storageAccounts/tx02v2tfstateb602d594/providers/Microsoft.Authorization/locks/tx02v2-state-cannot-delete"
  }
}

mock_resource "azurerm_consumption_budget_subscription" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Consumption/budgets/tx02v2-monthly"
  }
}

mock_resource "azurerm_virtual_network" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet"
  }
}

mock_resource "azurerm_subnet" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/mock"
  }
}

mock_resource "azurerm_network_security_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/networkSecurityGroups/tx02v2-lab-postgres"
  }
}

mock_resource "azurerm_network_security_rule" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/networkSecurityGroups/tx02v2-lab-postgres/securityRules/mock"
  }
}

mock_resource "azurerm_subnet_network_security_group_association" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/virtualNetworks/tx02v2-lab-vnet/subnets/postgres"
  }
}

mock_resource "azurerm_private_dns_zone" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/privateDnsZones/tx02v2-lab.private.postgres.database.azure.com"
  }
}

mock_resource "azurerm_private_dns_zone_virtual_network_link" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/privateDnsZones/tx02v2-lab.private.postgres.database.azure.com/virtualNetworkLinks/tx02v2-lab-vnet"
  }
}

mock_resource "azurerm_kubernetes_cluster" {
  defaults = {
    id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
    oidc_issuer_url        = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/55555555-5555-5555-5555-555555555555/"
    node_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab-nodes"
    fqdn                   = "tx02v2-lab-mock.hcp.eastus2.azmk8s.io"
  }
}

mock_resource "azurerm_log_analytics_workspace" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.OperationalInsights/workspaces/tx02v2-lab-logs"
    workspace_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  }
}

mock_resource "azurerm_application_insights" {
  defaults = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Insights/components/tx02v2-lab-traces"
    app_id              = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    instrumentation_key = "00000000-0000-0000-0000-000000000000"
    connection_string   = "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://eastus2-0.in.applicationinsights.azure.com/"
  }
}

mock_resource "azurerm_monitor_diagnostic_setting" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab|control-plane"
  }
}

mock_resource "azurerm_postgresql_flexible_server" {
  defaults = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.DBforPostgreSQL/flexibleServers/tx02v2-lab-postgres"
    fqdn = "tx02v2-lab-postgres.postgres.database.azure.com"
  }
}

mock_resource "azurerm_postgresql_flexible_server_configuration" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.DBforPostgreSQL/flexibleServers/tx02v2-lab-postgres/configurations/mock"
  }
}

mock_resource "azurerm_postgresql_flexible_server_database" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.DBforPostgreSQL/flexibleServers/tx02v2-lab-postgres/databases/dx02v2"
  }
}

mock_resource "azurerm_key_vault" {
  defaults = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.KeyVault/vaults/tx02v2-lab-b602d594"
    vault_uri = "https://tx02v2-lab-b602d594.vault.azure.net/"
  }
}

mock_resource "azurerm_key_vault_secret" {
  defaults = {
    id                      = "https://tx02v2-lab-b602d594.vault.azure.net/secrets/mock/0123456789abcdef0123456789abcdef"
    versionless_id          = "https://tx02v2-lab-b602d594.vault.azure.net/secrets/mock"
    version                 = "0123456789abcdef0123456789abcdef"
    resource_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.KeyVault/vaults/tx02v2-lab-b602d594/secrets/mock/versions/0123456789abcdef0123456789abcdef"
    resource_versionless_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.KeyVault/vaults/tx02v2-lab-b602d594/secrets/mock"
  }
}

mock_resource "azurerm_container_registry" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ContainerRegistry/registries/tx02v2labb602d594"
    login_server = "tx02v2labb602d594.azurecr.io"
  }
}

mock_resource "azurerm_application_load_balancer" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc"
  }
}

mock_resource "azurerm_application_load_balancer_frontend" {
  defaults = {
    id                          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc/frontends/tx02v2-lab-frontend"
    fully_qualified_domain_name = "mock0000.fz00.alb.azure.com"
  }
}

mock_resource "azurerm_application_load_balancer_subnet_association" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc/associations/tx02v2-lab-association"
  }
}

mock_resource "azurerm_web_application_firewall_policy" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/tx02v2-lab-waf"
  }
}

mock_resource "azurerm_application_load_balancer_security_policy" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc/securityPolicies/tx02v2-lab-waf"
  }
}

mock_resource "azurerm_app_configuration" {
  defaults = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.AppConfiguration/configurationStores/tx02v2-lab-b602d594"
    endpoint = "https://tx02v2-lab-b602d594.azconfig.io"
  }
}

mock_resource "azurerm_app_configuration_key" {
  defaults = {
    id = "https://tx02v2-lab-b602d594.azconfig.io/kv/mock?label=%00"
  }
}
