# User-assigned managed identities of the lab and the federated credentials of the two platform
# controllers (Microsoft Entra Workload ID: the pods exchange their ServiceAccount token from the
# AKS OIDC issuer for an Entra ID token; no client secret exists anywhere).

locals {
  workload_identity_audience = ["api://AzureADTokenExchange"]
}

# Control plane of AKS: Network Contributor on the node subnet and Managed Identity Operator on
# the kubelet identity, both before the cluster exists (roles.tf).
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.name}-aks"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

# Kubelets of the nodes: AcrPull on the registry (roles.tf).
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "${local.name}-kubelet"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

# External Secrets Operator: Key Vault Secrets User on the lab vault only (contract).
resource "azurerm_user_assigned_identity" "eso" {
  name                = "${local.name}-eso"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "eso" {
  name                      = "external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.eso.id
  issuer                    = module.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:external-secrets:external-secrets"
  audience                  = local.workload_identity_audience
}

# ALB Controller of Application Gateway for Containers (bring-your-own deployment, roles.tf).
resource "azurerm_user_assigned_identity" "alb" {
  name                = "${local.name}-alb"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "alb" {
  # The name used by the official ALB Controller quickstart.
  name                      = "azure-alb-identity"
  user_assigned_identity_id = azurerm_user_assigned_identity.alb.id
  issuer                    = module.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:azure-alb-system:alb-controller-sa"
  audience                  = local.workload_identity_audience
}
