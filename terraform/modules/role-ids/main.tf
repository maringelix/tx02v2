# Built-in Azure role definition IDs. They are public constants (the same in every tenant),
# verified on 2026-10-11 against the Azure built-in roles pages of learn.microsoft.com; the
# Application Gateway for Containers role comes from the AGC quickstarts (it is not listed there).
#
# This module is the only place in the Terraform code where role GUIDs live:
# - terraform/envs/lab assigns exactly these roles (and no other) to lab principals;
# - terraform/bootstrap puts exactly these GUIDs in the ABAC condition of the apply identity,
#   so the lab root cannot grant any other role (for example Owner).
# The harness allowlists these GUIDs by name (scripts/harness.sh, BUILTIN_ROLE_IDS).

locals {
  lab_assignable = {
    "App Configuration Data Reader"               = "516239f1-63e1-4d78-a4de-a74fb236a071"
    "AppGw for Containers Configuration Manager"  = "fbc52c3f-28ad-4303-a892-8a056630b8f1"
    "Azure Kubernetes Service Cluster User Role"  = "4abbcc35-e782-43d8-92c5-2d3f1bd2253f"
    "Azure Kubernetes Service RBAC Cluster Admin" = "b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b"
    "Container Registry Repository Reader"        = "b93aa761-3e63-49ed-ac28-beffa264f7ac"
    "Container Registry Repository Writer"        = "2a1e307c-b015-4ebd-883e-5b7698a07328"
    "Key Vault Secrets User"                      = "4633458b-17de-408a-b874-0445c86b69e6"
    "Managed Identity Operator"                   = "f1a07417-d97a-45cb-824c-7a7467783830"
    "Monitoring Metrics Publisher"                = "3913510d-42f4-4e42-8a64-420c390055eb"
    "Network Contributor"                         = "4d97b98b-1d4f-4787-a291-c67834d212e7"
    "Storage Blob Data Contributor"               = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    "Storage Blob Data Reader"                    = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
  }
}
