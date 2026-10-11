# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added

- Initial v2 of the Azure infrastructure lab, rebuilt from scratch with the lessons of v1
  (docs/ARQUITETURA.md, "v1 → v2"):
  - `terraform/bootstrap`: resource provider registrations, hardened state storage account (Entra ID
    only, versioning, soft delete, `CanNotDelete` lock), the `tx02v2-lab` resource group, the
    contract identities `tx02v2-gha-plan`, `tx02v2-gha-apply` and `dx02v2-gha-deploy` with GitHub
    federated credentials, least-privilege roles (plan: read roles the provider refresh needs; apply:
    lab-scoped roles and an ABAC-constrained role assignment right), monthly cost budget with Actual
    50/80/100 % and Forecasted 100 % alerts.
  - `terraform/envs/lab` with modules `network` (VNet, delegated subnets, PostgreSQL NSG, private DNS
    zone), `aks` (Kubernetes 1.36, Free tier, Entra ID + Azure RBAC, local accounts disabled,
    workload identity, Azure CNI Overlay + Cilium, Azure Linux system pool), `postgres` (Flexible
    Server 17, private access, write-only password, TLS parameters), `keyvault` (RBAC, write-only
    secrets), `acr` (Basic), `agc` (Application Gateway for Containers in bring-your-own mode, WAF
    policy with DRS 2.1 + Bot Manager 1.1 and its SecurityPolicy, `enable_waf` on by default),
    `appconfig` (contract store, Free tier) and `role-ids`; every role assignment of the lab in one
    file; the 15 contract keys.
  - `app_deployer_principal_ids` get the same Azure roles as `dx02v2-gha-deploy` (AcrPush, Azure
    Kubernetes Service Cluster User Role, App Configuration Data Reader) besides the RoleBinding
    subject, with tests for a list of deployers and for an empty list.
  - System node pool default `Standard_D2als_v6`; `node_vm_size` rejects B-series sizes, which AKS
    does not support in system node pools.
  - Multi-platform provider lock files (linux_amd64, linux_arm64, darwin_arm64, windows_amd64).
  - `terraform test` suites with a mocked azurerm provider for both roots and every module (71 runs).
  - `platform/`: ALB Controller 1.12.2 (chart SHA256 and running image digests verified) and External
    Secrets Operator 2.12.0 install and uninstall scripts, Helm values, namespace, deployer RBAC and
    ClusterSecretStore manifests rendered from the contract.
  - Harness (`scripts/harness.sh`, `make verify`, 32 checks) with pinned, SHA256-verified tools,
    including Azure policy checks (write-only secrets, Entra ID only, private PostgreSQL, no
    subscription-scope roles, contract tags, identifier and GUID scan).
  - GitHub workflows: `ci`, `terraform-plan`, `terraform-apply`, `platform`, `terraform-destroy`;
    ruleset and repository settings as code; Dependabot; issue and PR templates.
  - `scripts/leftovers.sh` to find billable or orphaned leftovers after a destroy.
  - Brazilian Portuguese docs: architecture, contract v1, runbook, costs (Azure Retail Prices API,
    2026-10-11), guardrails, harness, sustainment, publication checklist, and
    `docs/LICOES_APRENDIDAS.md` (sanitized lessons learned from the Azure v1 lab, December 2025 –
    January 2026).
