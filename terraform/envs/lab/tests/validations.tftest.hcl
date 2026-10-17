# Negative tests: unsafe or invalid inputs must be rejected before anything is planned.

mock_provider "azurerm" {
  source = "../../tests/mocks"
}

run "rejects_unknown_postgres_profile" {
  command = plan
  variables {
    postgres_profile = "production"
  }
  expect_failures = [var.postgres_profile]
}

run "rejects_burstable_ha_sku" {
  command = plan
  variables {
    postgres_profile = "ha"
    postgres_ha_sku  = "B_Standard_B1ms"
  }
  expect_failures = [var.postgres_ha_sku]
}

run "rejects_same_region_for_dr" {
  command = plan
  variables {
    postgres_profile = "dr"
    dr_location      = "eastus2"
  }
  expect_failures = [var.dr_location]
}

run "rejects_unsupported_ha_region" {
  command = plan
  variables {
    postgres_profile = "ha"
    location         = "brazilsouth"
  }
  expect_failures = [var.postgres_profile, check.location_matches_resource_group]
}

run "rejects_overlapping_dr_subnets" {
  command = plan
  variables {
    dr_postgres_subnet_cidr = "10.21.4.0/24"
  }
  expect_failures = [var.dr_vnet_cidr]
}

variables {
  github_owner                    = "maringelix"
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
  deploy_principal_id             = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  cluster_admin_principal_ids     = ["11111111-1111-1111-1111-111111111111"]
}

run "accepts_the_example_inputs" {
  command = plan
}

# --- API server ---

run "rejects_the_api_server_open_to_the_world_without_opt_in" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "accepts_the_api_server_open_to_the_world_with_explicit_opt_in" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["0.0.0.0/0"]
    allow_api_server_from_anywhere  = true
  }
}

run "rejects_an_empty_authorized_range_list" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = []
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_a_non_canonical_authorized_range" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = ["203.0.113.10/24"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

run "rejects_more_than_200_authorized_ranges" {
  command = plan

  variables {
    api_server_authorized_ip_ranges = [for i in range(201) : "10.${floor(i / 256)}.${i % 256}.0/24"]
  }

  expect_failures = [var.api_server_authorized_ip_ranges]
}

# --- Principals ---

run "rejects_an_empty_cluster_admin_list" {
  command = plan

  variables {
    cluster_admin_principal_ids = []
  }

  expect_failures = [var.cluster_admin_principal_ids]
}

run "rejects_a_cluster_admin_that_is_not_a_guid" {
  command = plan

  variables {
    cluster_admin_principal_ids = ["you@example.com"]
  }

  expect_failures = [var.cluster_admin_principal_ids]
}

run "rejects_an_uppercase_guid" {
  command = plan

  variables {
    deploy_principal_id = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
  }

  expect_failures = [var.deploy_principal_id]
}

run "rejects_the_deployer_as_cluster_admin" {
  command = plan

  variables {
    cluster_admin_principal_ids = ["dddddddd-dddd-dddd-dddd-dddddddddddd"]
  }

  expect_failures = [var.cluster_admin_principal_ids]
}

run "rejects_the_deployer_repeated_in_app_deployers" {
  command = plan

  variables {
    app_deployer_principal_ids = ["dddddddd-dddd-dddd-dddd-dddddddddddd"]
  }

  expect_failures = [var.app_deployer_principal_ids]
}

run "rejects_a_bad_app_deployer_id" {
  command = plan

  variables {
    app_deployer_principal_ids = ["not-a-guid"]
  }

  expect_failures = [var.app_deployer_principal_ids]
}

# --- AKS ---

run "rejects_a_patch_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.36.1"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_a_prefixed_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "v1.36"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_a_bad_vm_size" {
  command = plan

  variables {
    node_vm_size = "d2als_v6"
  }

  expect_failures = [var.node_vm_size]
}

run "rejects_a_b_series_system_pool" {
  command = plan

  variables {
    node_vm_size = "Standard_B2als_v2"
  }

  expect_failures = [var.node_vm_size]
}

run "rejects_inconsistent_node_counts" {
  command = plan

  variables {
    node_count     = 4
    node_max_count = 3
  }

  expect_failures = [var.node_count]
}

run "rejects_a_system_pool_that_scales_to_zero" {
  command = plan

  variables {
    node_min_count = 0
    node_count     = 1
  }

  expect_failures = [var.node_min_count]
}

run "rejects_a_zero_log_quota" {
  command = plan

  variables {
    log_daily_quota_gb = 0
  }

  expect_failures = [var.log_daily_quota_gb]
}

# --- Network ---

run "rejects_a_non_canonical_vnet_cidr" {
  command = plan

  variables {
    vnet_cidr = "10.20.1.0/16"
  }

  expect_failures = [var.vnet_cidr]
}

run "rejects_an_agc_subnet_smaller_than_a_24" {
  command = plan

  variables {
    agc_subnet_cidr = "10.20.4.0/25"
  }

  expect_failures = [var.agc_subnet_cidr]
}

run "rejects_an_agc_subnet_larger_than_a_24" {
  command = plan

  variables {
    # Canonical, inside the VNet and overlapping nothing: only the exact /24 rule rejects it.
    agc_subnet_cidr = "10.20.8.0/23"
  }

  expect_failures = [var.agc_subnet_cidr]
}

run "rejects_an_agc_subnet_overlapping_the_nodes" {
  command = plan

  variables {
    agc_subnet_cidr = "10.20.2.0/24"
  }

  expect_failures = [var.agc_subnet_cidr]
}

run "rejects_a_postgres_subnet_outside_the_vnet" {
  command = plan

  variables {
    postgres_subnet_cidr = "10.30.5.0/24"
  }

  expect_failures = [var.postgres_subnet_cidr]
}

run "rejects_a_postgres_subnet_overlapping_the_agc_subnet" {
  command = plan

  variables {
    postgres_subnet_cidr = "10.20.4.128/25"
  }

  expect_failures = [var.postgres_subnet_cidr]
}

run "rejects_a_pod_cidr_overlapping_the_vnet" {
  command = plan

  variables {
    pod_cidr = "10.20.0.0/16"
  }

  expect_failures = [var.pod_cidr]
}

run "rejects_a_service_cidr_overlapping_the_vnet" {
  command = plan

  variables {
    service_cidr   = "10.20.0.0/16"
    dns_service_ip = "10.20.0.10"
  }

  expect_failures = [var.service_cidr]
}

run "rejects_a_dns_service_ip_outside_the_service_cidr" {
  command = plan

  variables {
    dns_service_ip = "10.1.0.10"
  }

  expect_failures = [var.dns_service_ip]
}

run "rejects_the_first_address_of_the_service_cidr_as_dns" {
  command = plan

  variables {
    dns_service_ip = "10.0.0.1"
  }

  expect_failures = [var.dns_service_ip]
}

# --- Other ---

run "rejects_a_bad_location" {
  command = plan

  variables {
    location = "East US 2"
  }

  expect_failures = [var.location]
}

run "rejects_a_short_postgres_backup_retention" {
  command = plan

  variables {
    postgres_backup_retention_days = 1
  }

  expect_failures = [var.postgres_backup_retention_days]
}

run "placeholder_owner_is_refused" {
  command = plan

  variables {
    github_owner = "your-github-user"
  }

  expect_failures = [var.github_owner]
}
