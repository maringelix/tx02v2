# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Security

- `github_owner` has no default any more (`terraform/bootstrap` and `terraform/envs/lab`): a fork that
  kept the default would have created CI identities that trust the workflows of another owner. The
  bootstrap refuses the placeholders of `terraform.tfvars.example` (`your-github-user` and the alert
  e-mail `you@example.com`); the workflows pass `github.repository_owner` to the lab root. New tests
  `placeholder_owner_is_refused` and `placeholder_alert_email_is_refused`.

### Changed

- The family table of both READMEs links the family hub `tx00v2` (roadmap, family guardrails,
  cross-repo checks).
- `docs/GUARDRAILS.md` and `docs/ARQUITETURA.md` no longer say that the end-to-end run of the local
  lab is pending: the CI job `e2e` runs it on every pull request.
- `scripts/repo-guardrails.sh` also turns issues on (the issue forms) and requires approval for
  workflow runs from forks of external contributors; the reviewer of the `lab` environment is the gh
  user that runs it. It fails while the workflows of a fork are still disabled and notes a renamed
  repository or a CODEOWNERS that names someone else (tested against a stub gh, then applied to the
  original repository and read back with `gh api` on 2026-10-14).
- The ruleset requires the CI job `e2e` too (`.github/rulesets/main.json`, applied with
  `scripts/repo-guardrails.sh`): the local lab is a merge gate, not only maintainer discipline.
- README status matrix: repository settings as code are applied (read back with `gh api` on
  2026-10-13), no longer `planned`.

### Added

- Local lab, "Observability 2.0" (ported from tx01v2; the last step of the v1 roadmap, never started
  there): Tempo 3.1.0 (grafana-community chart 3.1.0) and the OpenTelemetry Collector contrib 0.162.0
  (chart 0.176.0) in the observability layer; every Istio Gateway reports its spans (Telemetry
  `mesh-default`); spanmetrics with exemplars (scraped every 10 s: an exemplar lives one flush);
  Grafana links logs, metrics and traces. Alertmanager also posts warning and critical alerts to Slack
  (Secret `monitoring/alertmanager-slack`, `LOCAL_SLACK_WEBHOOK_URL`; without it the sink gets the Slack
  message and a probe checks it). Chaos with hypotheses: NetworkChaos (100 ms) and StressChaos (CPU +
  memory) next to the pod kill. The edge keeps a UUID-shaped `X-Request-Id` as sent. Local contract
  version 2 (`tracing.otlp-endpoint`). 34 probes (was 26).
- Contract version 2 (`not run in the cloud (v2)`): the cloud platform layer installs the same
  Collector in the namespace `observability`, exporting to the new Application Insights
  `tx02v2-lab-traces` (workspace-based, local authentication off: ingestion only with the Entra token
  of the Collector, extension `azure_auth`). New identity `tx02v2-lab-otel` (Workload ID,
  `observability/opentelemetry-collector`) with the new built-in role `Monitoring Metrics Publisher`
  on that resource only: a role widening of `modules/role-ids` that also changes the ABAC condition of
  `tx02v2-gha-apply` (re-apply the bootstrap). Ingestion is billed per GB, capped by
  `log_daily_quota_gb` (docs/CUSTOS.md). `platform/uninstall.sh` removes the release; tests and the
  `contract-platform`/`helm-template` checks cover the identity, role, resource, namespace, service
  account, exporter and digest.
- `FORK.md`: forking the lab step by step (what GitHub does not copy to a fork, the repository
  settings, the local lab, your own cloud account, troubleshooting), linked from both READMEs and
  CONTRIBUTING.md; the harness requires it.
- The devcontainer has Docker-in-Docker, so `make e2e` runs inside it (verified locally with
  `LOCAL_PROFILE=core`), and declares 4 CPUs and 8 GB; the harness checks that devcontainer features
  are pinned by digest.
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
