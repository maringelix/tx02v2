# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Changed

- The ruleset requires the CI job `e2e` too (`.github/rulesets/main.json`, applied with
  `scripts/repo-guardrails.sh`): the local lab is a merge gate, not only maintainer discipline.
- README status matrix: repository settings as code are applied (read back with `gh api` on
  2026-10-13), no longer `planned`.

### Added

- The local lab (docs/LAB_LOCAL.md), ported from tx01v2: the whole v1 platform on Docker, with no
  cloud account. `make e2e` verified locally and in CI (26 probes, destroy with no leftovers).
  - `terraform/envs/local` (providers docker 4.6.0, tls 4.4.1, random 3.9.1): network
    `tx02v2-local` (`10.251.0.0/24`), kind 1.36 cluster, emulated ACR (registry 3.1.2, push to
    `localhost:5002`), PostgreSQL Flexible Server (PostgreSQL 17, TLS only, lab CA), Blob Storage
    (Versity S3 Gateway 1.8.0, S3 API), load balancer (cloud-provider-kind 0.12.0) and git server
    (Soft Serve 0.12.3); 10 `terraform test` runs (plan only, mocked providers). Network and registry
    port differ from tx01v2 (`10.250.0.0/24`, `5001`) so the two labs never collide.
  - `platform/local`: Gateway API 1.6.3, Istio 1.31.1 ambient, cert-manager 1.21.2 (`lab-ca`),
    External Secrets 2.12.0 (`local-secrets`, on top of `platform/values/external-secrets.yaml`),
    metrics-server, kube-prometheus-stack 92.3.0 with an in-cluster alert sink, Loki 7.3.0 + Alloy
    1.13.1, Argo CD 10.10.3, Gatekeeper 3.23.1 with six policies from v1 in `deny`, Trivy Operator
    0.37.0, Velero 12.2.1 (AWS/S3 plugin against the emulator only), Chaos Mesh 2.8.4; charts pinned
    by version and SHA256, images by digest (same pins as tx01v2); profiles `core`, `observability`,
    `operations`, `full`.
  - The edge keeps an external `X-Request-Id` (EnvoyFilter `gateway-preserve-request-id`), as the
    dx02v2 smoke on kind expects; Application Gateway for Containers assigns its own id in Azure (not
    emulated). Trivy Operator in ClientServer mode with the built-in Trivy server.
  - The dx02v2 local deploy targets: AppProject `dx02v2`, Secrets `lab-secrets/tx02v2-lab-db-app`,
    `lab-secrets/tx02v2-lab-app-admin-token` (the Key Vault secret names of contract v1) and
    `lab-secrets/gitops-push-key`, namespace `monitoring` in the ambient mesh.
  - `platform/local/check.sh`: 26 probes with real traffic or API calls (mTLS and authorization,
    HTTPS through the emulated load balancer, X-Request-Id pass-through, alert delivery, logs, GitOps
    sync and self-heal, policy denials, vulnerability reports, backup/restore drill, chaos experiment
    with a hypothesis).
  - `scripts/local-lab.sh` (up, down, check, e2e, kubeconfig, status) and
    `scripts/leftovers-local.sh`; local contract `lab-system/lab-contract` (docs/CONTRATO.md).
  - Harness: checks `local-versions`, `helm-template-local`, `kubeconform-local`, `policy-gator`,
    `terraform-validate:envs/local`, `terraform-test:envs/local`; stage `e2e` (`local-lab-e2e`,
    `make e2e`) and the CI job `e2e`; tools kind 0.33.0 and gator 3.23.1. `policy-terraform` allows
    `random_password` only in `terraform/envs/local` and forbids cloud providers, remote backends,
    `0.0.0.0` ports and privileged containers there; `trivy-config` skips the gator fixtures.

### Fixed

- `platform/local/uninstall.sh`: the teardown no longer fails when the Service of a Gateway that is
  being deleted disappears between the listing and the delete (`--ignore-not-found`); seen in the
  app repo platform e2e, where the app Gateway still exists at teardown.

### Added (first v2)

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

### Changed (after the first push)

- The CI (`static`, `test`) ran green on GitHub: the README status matrix now says `verified in CI`
  for those rows; AGENTS.md and docs/SUSTENTACAO.md follow.
- The README family table and AGENTS.md link the Google Cloud pair (`tx03v2`, `dx03v2`), now public.
