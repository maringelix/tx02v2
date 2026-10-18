# Traces of the app (contract v2): the OpenTelemetry Collector of the platform layer (namespace
# observability, platform/install.sh) writes the spans of dx02v2 to this Application Insights resource.
# Ingestion needs a Microsoft Entra token: local authentication (the instrumentation key alone) is off,
# so the connection string that install.sh reads is an address, not a secret. Billing is the Log
# Analytics ingestion per GB (docs/COSTS.md); the daily caps bound it.

resource "azurerm_log_analytics_workspace" "traces" {
  name                         = "${local.name}-traces"
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.lab.name
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  daily_quota_gb               = var.log_daily_quota_gb
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_application_insights" "traces" {
  name                         = "${local.name}-traces"
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.lab.name
  workspace_id                 = azurerm_log_analytics_workspace.traces.id
  application_type             = "other"
  local_authentication_enabled = false
  daily_data_cap_in_gb         = var.log_daily_quota_gb
  tags                         = local.tags
}

# The Collector: Monitoring Metrics Publisher on this Application Insights resource only (roles.tf),
# through Microsoft Entra Workload ID (observability/opentelemetry-collector).
resource "azurerm_user_assigned_identity" "otel" {
  name                = "${local.name}-otel"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "otel" {
  name                      = "opentelemetry-collector"
  user_assigned_identity_id = azurerm_user_assigned_identity.otel.id
  issuer                    = module.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:observability:opentelemetry-collector"
  audience                  = local.workload_identity_audience
}
