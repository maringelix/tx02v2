resource "azurerm_log_analytics_workspace" "traces_dr" {
  count                        = var.postgres_profile == "dr" ? 1 : 0
  name                         = "${local.name}-dr-traces"
  location                     = var.dr_location
  resource_group_name          = data.azurerm_resource_group.lab.name
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  daily_quota_gb               = var.log_daily_quota_gb
  local_authentication_enabled = false
  tags                         = local.tags
}
resource "azurerm_application_insights" "traces_dr" {
  count                        = var.postgres_profile == "dr" ? 1 : 0
  name                         = "${local.name}-dr-traces"
  location                     = var.dr_location
  resource_group_name          = data.azurerm_resource_group.lab.name
  workspace_id                 = azurerm_log_analytics_workspace.traces_dr[0].id
  application_type             = "other"
  local_authentication_enabled = false
  daily_data_cap_in_gb         = var.log_daily_quota_gb
  tags                         = local.tags
}
resource "azurerm_monitor_metric_alert" "replica_lag" {
  count               = var.postgres_profile == "dr" ? 1 : 0
  name                = "${local.name}-dr-replica-lag"
  resource_group_name = data.azurerm_resource_group.lab.name
  scopes              = [azurerm_postgresql_flexible_server.replica[0].id]
  description         = "Replica lag above 60 seconds; review backup freshness and fence writers before promotion."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "physical_replication_delay_in_seconds"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 60
  }
  tags = local.tags
}
