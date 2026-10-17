# Remote state storage hardening, resource groups and resource provider registrations.

mock_provider "azurerm" {
  source = "../tests/mocks"
}

variables {
  github_owner         = "maringelix"
  github_owner_id      = "1000000"
  tx02v2_repository_id = "2000000"
  dx02v2_repository_id = "3000000"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  budget_alert_emails  = ["lab-alerts@example.org"]
}

override_resource {
  target = azurerm_resource_group.bootstrap
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-bootstrap"
  }
}

run "state_account_is_hardened" {
  command = apply

  assert {
    condition     = azurerm_storage_account.state.name == "tx02v2tfstateb602d594" && azurerm_storage_account.state.resource_group_name == "tx02v2-bootstrap"
    error_message = "The state account must be tx02v2tfstate<substr(sha1(subscription_id), 0, 8)> in tx02v2-bootstrap."
  }

  assert {
    condition = (
      azurerm_storage_account.state.account_kind == "StorageV2" &&
      azurerm_storage_account.state.min_tls_version == "TLS1_2" &&
      azurerm_storage_account.state.https_traffic_only_enabled
    )
    error_message = "The state account must be StorageV2, TLS 1.2 minimum and HTTPS only."
  }

  assert {
    condition = (
      azurerm_storage_account.state.shared_access_key_enabled == false &&
      azurerm_storage_account.state.default_to_oauth_authentication &&
      azurerm_storage_account.state.local_user_enabled == false &&
      azurerm_storage_account.state.sftp_enabled == false
    )
    error_message = "Shared keys, local users and SFTP must be off: Entra ID only."
  }

  assert {
    condition     = azurerm_storage_account.state.allow_nested_items_to_be_public == false && azurerm_storage_container.state.container_access_type == "private"
    error_message = "No anonymous/public blob access: the container is private."
  }

  assert {
    condition     = azurerm_storage_account.state.cross_tenant_replication_enabled == false && azurerm_storage_account.state.infrastructure_encryption_enabled
    error_message = "No cross-tenant replication; infrastructure (double) encryption on."
  }

  assert {
    condition = (
      azurerm_storage_account.state.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 7 &&
      azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 7
    )
    error_message = "Blob versioning plus 7-day blob and container soft delete must be on."
  }

  assert {
    condition     = azurerm_storage_container.state.name == "tfstate" && azurerm_storage_container.state.storage_account_id == azurerm_storage_account.state.id
    error_message = "The lab state lives in the private container tfstate of the state account."
  }

  assert {
    condition = (
      azurerm_role_assignment.state_operator.scope == azurerm_storage_container.state.id &&
      azurerm_role_assignment.state_operator.role_definition_name == "Storage Blob Data Contributor" &&
      azurerm_role_assignment.state_operator.principal_id == "99999999-9999-9999-9999-999999999999"
    )
    error_message = "The human running the bootstrap needs Storage Blob Data Contributor on the container (Owner has no data actions)."
  }

  assert {
    condition     = output.backend_hcl == "storage_account_name = \"tx02v2tfstateb602d594\"\n"
    error_message = "backend_hcl must be ready to paste into terraform/envs/lab/backend.hcl."
  }

  assert {
    condition = (
      length(azurerm_management_lock.state) == 1 &&
      azurerm_management_lock.state[0].lock_level == "CanNotDelete" &&
      azurerm_management_lock.state[0].scope == azurerm_storage_account.state.id
    )
    error_message = "The state account must carry a CanNotDelete lock by default."
  }

  assert {
    condition     = azurerm_resource_group.bootstrap.name == "tx02v2-bootstrap" && azurerm_resource_group.lab.name == "tx02v2-lab" && azurerm_resource_group.lab.location == "eastus2"
    error_message = "The bootstrap creates tx02v2-bootstrap and the (empty) tx02v2-lab resource group."
  }

  assert {
    # Only the tags attributes are compared (whole objects of the storage account carry
    # sensitive attributes that must stay out of test diagnostics).
    condition = alltrue([
      for t in [azurerm_resource_group.bootstrap.tags, azurerm_resource_group.lab.tags, azurerm_storage_account.state.tags, azurerm_user_assigned_identity.plan.tags] :
      t == tomap({ Project = "tx02v2", Environment = "lab", ManagedBy = "terraform", Repository = "maringelix/tx02v2", Stack = "bootstrap" })
    ])
    error_message = "Bootstrap resources carry the contract tags plus Stack=bootstrap."
  }
}

run "the_lock_is_lifted_only_on_purpose" {
  command = plan

  variables {
    state_protection_lock = false
  }

  assert {
    condition     = length(azurerm_management_lock.state) == 0
    error_message = "state_protection_lock = false must remove the lock (final teardown)."
  }
}

run "resource_providers_of_the_lab_are_registered" {
  command = plan

  assert {
    condition = toset(local.resource_providers) == toset([
      "Microsoft.AppConfiguration",
      "Microsoft.Compute",
      "Microsoft.Consumption",
      "Microsoft.ContainerRegistry",
      "Microsoft.ContainerService",
      "Microsoft.DBforPostgreSQL",
      "Microsoft.Insights",
      "Microsoft.KeyVault",
      "Microsoft.ManagedIdentity",
      "Microsoft.Network",
      "Microsoft.NetworkFunction",
      "Microsoft.OperationalInsights",
      "Microsoft.ServiceNetworking",
      "Microsoft.Storage",
    ])
    error_message = "The bootstrap provider must register every resource provider the lab uses."
  }

  assert {
    condition     = output.appconfig_endpoint == "https://tx02v2-lab-b602d594.azconfig.io"
    error_message = "The App Configuration endpoint is deterministic (dx02v2 variable AZURE_APPCONFIG_ENDPOINT)."
  }
}

run "rejects_a_bad_subscription_id" {
  command = plan

  variables {
    subscription_id = "not-a-guid"
  }

  expect_failures = [var.subscription_id]
}

run "rejects_a_bad_location" {
  command = plan

  variables {
    location = "East US 2"
  }

  expect_failures = [var.location]
}
run "state_can_survive_regional_loss" {
  command = apply
  variables { state_replication_type = "RAGRS" }
  assert {
    condition     = azurerm_storage_account.state.account_replication_type == "RAGRS" && azurerm_storage_account.state.blob_properties[0].versioning_enabled
    error_message = "Regional recovery needs both geo replication and state object versions."
  }
}
