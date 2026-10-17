mock_provider "azurerm" {
  source = "../../tests/mocks"
}

variables {
  github_owner                    = "maringelix"
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111"]
}

run "core_has_no_secondary_region" {
  command = plan
  assert {
    condition = (
      length(module.aks_dr) == 0 && length(module.acr_dr) == 0 &&
      length(azurerm_postgresql_flexible_server.replica) == 0 &&
      length(azurerm_virtual_network_peering.primary_to_dr) == 0
    )
    error_message = "Core must not reserve secondary region resources."
  }
}

run "postgres_delete_lock_is_opt_in_and_database_scoped" {
  command = apply
  variables {
    postgres_delete_lock = true
  }
  assert {
    condition     = azurerm_management_lock.postgres[0].lock_level == "CanNotDelete" && azurerm_management_lock.postgres[0].scope == module.postgres.server_id
    error_message = "The opt-in delete lock protects only the PostgreSQL server, never the subscription or entire lab."
  }
}

run "dr_uses_a_second_region_and_private_replica" {
  command = apply
  variables {
    postgres_profile = "dr"
  }
  assert {
    condition = (
      azurerm_postgresql_flexible_server.replica[0].location == "centralus" &&
      azurerm_postgresql_flexible_server.replica[0].create_mode == "Replica" &&
      azurerm_postgresql_flexible_server.replica[0].source_server_id == module.postgres.server_id &&
      azurerm_postgresql_flexible_server.replica[0].public_network_access_enabled == false &&
      module.aks_dr[0].cluster_name == "tx02v2-lab-dr" &&
      module.network_dr[0].vnet_name == "tx02v2-lab-dr-vnet" &&
      module.network_dr[0].vnet_cidr == "10.21.0.0/16"
    )
    error_message = "DR requires independent AKS/VNet and a private PostgreSQL replica in another region."
  }
  assert {
    condition = (
      length(azurerm_virtual_network_peering.primary_to_dr) == 1 &&
      length(azurerm_virtual_network_peering.dr_to_primary) == 1 &&
      length(azurerm_private_dns_zone_virtual_network_link.primary_sql_from_dr) == 1 &&
      length(azurerm_private_dns_zone_virtual_network_link.dr_sql_from_primary) == 1 &&
      length(azurerm_federated_identity_credential.dr) == 5 &&
      azurerm_federated_identity_credential.dr["eso"].subject == "system:serviceaccount:external-secrets:external-secrets" &&
      azurerm_federated_identity_credential.dr["eso"].issuer == module.aks_dr[0].oidc_issuer_url
    )
    error_message = "DR replication needs both private network directions/DNS and exact secondary OIDC subjects."
  }
  assert {
    condition = (
      endswith(module.acr_dr[0].name, "dr") &&
      endswith(module.keyvault_dr[0].name, "-dr") &&
      module.keyvault_dr[0].manages_values == false &&
      endswith(module.appconfig_dr[0].name, "-dr") &&
      module.velero_dr[0].storage_account_name != module.velero.storage_account_name
    )
    error_message = "Registry, secrets, config and backup storage must have independent secondary names."
  }
  assert {
    condition = (
      azurerm_application_insights.traces_dr[0].location == "centralus" &&
      azurerm_role_assignment.dr["alb_configuration"].scope == module.agc_dr[0].id &&
      azurerm_monitor_metric_alert.replica_lag[0].criteria[0].metric_name == "physical_replication_delay_in_seconds" &&
      basename(azurerm_role_assignment.dr["velero_recovery"].role_definition_id) == module.roles.lab_assignable["Storage Blob Data Reader"] &&
      azurerm_role_assignment.dr["velero_recovery"].scope == module.velero.container_id
    )
    error_message = "DR needs regional telemetry and lag monitoring; recovery reads only the primary backup container."
  }
}
