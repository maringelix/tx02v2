# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Documentation

- Translate all public documentation and historical evidence into English, adopt canonical English filenames, and link the central getting-started guide. Correct Azure onboarding to the current bootstrap, protected workflows, FinOps inputs, signed-image publication/promotion, and full-profile DNS/backup prerequisites.
- Replace the bilingual README gate with English status/onboarding coverage while preserving existing structure and honesty checks.

### Fixed

- Cloud-readiness audit: full standby ACME rendering now accepts only the exact primary or
  secondary AGC/frontend pair selected by the operator. Mixed pairs and unrelated targets fail.
- The full OpenTelemetry Collector upgrade explicitly retains its Azure Workload ID client-ID
  annotation, rather than relying on values from the earlier core Helm release.
- Image-signature admission uses Kyverno's Kubernetes evaluation mode for Pod image extractors.
  Offline regression tests parse the rendered policy and reject JSON-mode/audit-only mutations;
  installer fixtures execute the core/full functions with simulated external mutations and real
  Helm value merging. Real Azure authentication, TLS issuance and signature admission still require
  an approved cloud run; none has been executed in Azure (v2).

- R9: build selectable regional platform/GitOps, current-credential synchronization, regional
  tracing, native lag alerts, RAGRS recovery reads and state option, plus portable PVC data backup.

### Added

- R9 Velero PVC recovery exercise: remove the original claim, PV and bytes, restore through
  Kopia, require a new claim UID and identical SHA256. The local Velero node agent needs root
  and kubelet hostPath; the server and application keep their restricted security contexts.
  A private random repository password is generated before the first backup and preserved.

- R9 continuity profiles `core|ha|dr`: opt-in zone-redundant PostgreSQL on General Purpose,
  configurable retention/PITR and geo backups, scoped delete lock, private cross-region replica,
  independent secondary AKS/VNet/ACR/Key Vault/App Configuration/AGC/Velero and exact Workload
  Identity subjects. Local physical PostgreSQL backup and WAL/PITR drill rejects corrupt backups.
  Cloud execution remains not run in Azure (v2); the R9 app proof is coordinated with dx02v2.

- Local R8 platform creates and waits for the ambient waypoint and enrolls the app namespace,
  including ingress traffic. This matches the Azure full profile's L7 identity policies and
  prevents the app's default-deny network rules from pointing at an absent waypoint.

- Optional lab-owned Azure DNS zone and app CNAME, with validated fork inputs and mocked Terraform
  tests. The full platform profile bootstraps a public Let's Encrypt certificate over AGC Gateway
  API HTTP-01 before enabling the app's HTTPS listener; core remains the low-cost HTTP exercise.

- Azure profile `full` with 16 pinned charts, ambient Istio with an L7 waypoint, app SLO metrics and
  dashboard, Argo CD GitOps, Gatekeeper, Kyverno image-signature admission, Trivy scans of private
  ACR repositories, Velero on Azure Blob through Workload ID with 35-day retention, and Chaos Mesh.
  The platform workflow keeps `core` as its default.
- Terraform Velero module with keyless StorageV2, a private Blob container, container-scoped data
  role and federated ServiceAccount identity. `LAB_NODE_VM_SIZE` and `LAB_NODE_COUNT` let cloud
  workflows size the cluster for the full profile while preserving core defaults.
- ACR Standard with repository-scoped ABAC: kubelet, Trivy and Kyverno read only the application
  repositories, while the deploy identities can write only those repositories.

### Changed

- The local platform installs the SHA256-pinned experimental Gateway API 1.6.3 CRDs so the R8
  waypoint exercise can validate bounded HTTPRoute retries without the standard channel pruning them.
- Cloud contract version 4 publishes the app hostname and ACME contact as two additional App
  Configuration keys. The coordinated dx02v2 full overlay consumes the resulting TLS Secret.

- Cloud contract version 3 previously added ambient and Gatekeeper namespace labels, GitOps and
  backup semantics. The separate local contract remains version 2.
- The full profile's image promotion, SLO, storage, waypoint and public TLS requirements are
  documented in `docs/CONTRACT.md`.

### Security

- The cloud path no longer trusts anyone who registers a deleted account name, it works for the
  repositories GitHub creates now, and the plan identity reads no secret (roadmap R3.13, R3.15,
  R3.16, R3.17):
  - The federated credentials pin the immutable subject,
    `repo:<owner>@<owner id>/<repository>@<repository id>:<context>`, which every repository created
    after 2026-07-15 (a fork too) emits; the name-based subject no longer matched them. New bootstrap
    variables `github_owner_id`, `tx02v2_repository_id` and `dx02v2_repository_id` (the `gh api`
    commands are in `docs/RUNBOOK.md`).
  - `scripts/repo-guardrails.sh` (same file in the six lab repositories) fails, instead of skipping,
    when it cannot protect the environment `lab`; it leaves only `main` in it, reads it back, fails
    when the OIDC subject of the repository is name-based and refuses an argument that is not the
    repository of the clone.
  - `tx02v2-gha-plan` has `Reader` on the lab and the state, nothing else: no `Key Vault Secrets User`,
    no `App Configuration Data Reader`, no AKS credential, no custom `ListKeys` role. The plan runs with
    `-refresh=false` (ADR 14).
  - The lists of people and addresses (`LAB_API_SERVER_AUTHORIZED_IP_RANGES`,
    `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS`, `LAB_APP_DEPLOYER_PRINCIPAL_IDS`) are secrets, masked element
    by element; the job summary and the artifacts replace CIDRs and IPs. New output
    `github_secrets_tx02v2`; `policy-workflows` enforces all of it.
  - `scripts/leftovers.sh` takes the subscription explicitly (`--subscription`) and counts as
    leftover only what is the lab's (tag `Project=tx02v2` or the groups `tx02v2-lab` and
    `tx02v2-lab-nodes`): the same kinds of resource of other work are INFO "(not the lab's)". It prints
    the exact purge command of each soft-deleted vault and App Configuration store. New check
    `leftovers-flow` runs it against a simulated subscription that also holds other work.
- Scripts act only on what the lab created, so whoever forks it can run them on a machine and a
  subscription that also hold other work:
  - `platform/uninstall.sh` (it deletes every Route, Gateway, Application Gateway for Containers
    object and LoadBalancer Service of the cluster and uninstalls three Helm releases) no longer reads
    `RESOURCE_GROUP` and `CLUSTER_NAME` from the environment, names many AKS guides export for other
    work, and `scripts/lib/azure.sh` no longer reads `LAB_PROJECT`, `LAB_NAME` or `LAB_KEY_PREFIX`:
    the target is the contract cluster `tx02v2-lab`, and the platform scripts refuse a cluster
    without the tag `Project=tx02v2` (`require_lab_cluster`).
  - The output `get_credentials_command` writes the kubeconfig of the lab to its own file
    (`/tmp/tx02v2-lab.kubeconfig`) and kubelogin converts only that file: `~/.kube/config`, its
    current context and the other Azure users in it stay as they were.
  - The scripts of `platform/local` refuse any kube context but `kind-tx02v2-local`
    (`require_lab_context`), also when one of them runs on its own: `platform/local/uninstall.sh`
    deletes every Gateway and LoadBalancer Service of the cluster it reaches.
  - The PostgreSQL Flexible Server is now `tx02v2-lab-<suffix>-postgres`: its name is a global DNS
    name, so the fixed `tx02v2-lab-postgres` let the lab of one fork block the apply of every other
    one, after AKS and the gateway were already billing.
  - New static check `policy-scripts` keeps all of this from coming back.
- `github_owner` has no default any more (`terraform/bootstrap` and `terraform/envs/lab`): a fork that
  kept the default would have created CI identities that trust the workflows of another owner. The
  bootstrap refuses the placeholders of `terraform.tfvars.example` (`your-github-user` and the alert
  e-mail `you@example.com`); the workflows pass `github.repository_owner` to the lab root. New tests
  `placeholder_owner_is_refused` and `placeholder_alert_email_is_refused`.

### Changed

- Comments, script messages and docs say "the contract" or point to `docs/CONTRACT.md` instead of
  "contract v1": the contract has been at version 2 since round 1 (roadmap S.8); the README says that HTTPS on the gateway listener is outside contract v2.
- The family table of both READMEs links the family hub `tx00v2` (roadmap, family guardrails,
  cross-repo checks).
- `docs/GUARDRAILS.md` and `docs/ARCHITECTURE.md` no longer say that the end-to-end run of the local
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

- `scripts/destroy.sh` (roadmap R3.14), run by `terraform-destroy`: the platform uninstall may fail
  and the destroy goes on; the workflow has an optional `force_unlock_id` input for the lease of an
  interrupted apply, and the leftover check runs with `if: always()`. New check `destroy-flow` runs the
  script with simulated `az`, `terraform`, `kubectl`, `helm` and `kubelogin`; `docs/RUNBOOK.md`
  documents the recovery.
- Pre-flight of `scripts/local-lab.sh up` (roadmap R3.18): the Docker CLI and the Terraform provider
  must talk to the same daemon, the lab network must not overlap a Docker network or a route of the
  machine, the registry port must be free. `down` and `e2e` refuse a lab that their state directory
  did not create, and `e2e` refuses a lab that is already up (it would destroy it). `make clean`
  removes things only under the directory of the Makefile. The pre-flight is also
  `scripts/local-lab.sh preflight`, and the new check `local-preflight` runs it against a simulated
  `docker`, `kind` and `ip`.
- `LOCAL_SIZE=small` for the local platform (roadmap R1.8, the port of tx01v2):
  `platform/local/values/small/<chart>.yaml` goes last in `helm_install`, with smaller memory limits
  and `GOMEMLIMIT` below them, 2 h of retention in Prometheus and 1 h in Tempo, no cAdvisor, kubelet
  probes or apiserver histogram series (and no default rules that read them), Grafana without unified
  alerting, fewer Argo CD workers, one Trivy scan job at a time and a lower limit for the operator,
  and the Gatekeeper audit every 5 minutes on the kinds the constraints match.
  `scripts/local/kind-cluster.sh` appends `terraform/envs/local/kind-config-small.yaml` (`GOMEMLIMIT`
  for the API server, the controller manager and etcd). The components stay the same. At the small
  size the full platform with the app of dx02v2 passes in 7 GB (18 probes in about 15 minutes, 4.35
  GiB of anonymous memory; CI job `e2e-platform-small` of dx02v2). The `helm-template-local` check
  renders every chart with an overlay a second time and fails when the overlay changes an image or
  names a chart that does not exist.
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
  `log_daily_quota_gb` (docs/COSTS.md). `platform/uninstall.sh` removes the release; tests and the
  `contract-platform`/`helm-template` checks cover the identity, role, resource, namespace, service
  account, exporter and digest.
- `FORK.md`: forking the lab step by step (what GitHub does not copy to a fork, the repository
  settings, the local lab, your own cloud account, troubleshooting), linked from both READMEs and
  CONTRIBUTING.md; the harness requires it.
- The devcontainer has Docker-in-Docker, so `make e2e` runs inside it (verified locally with
  `LOCAL_PROFILE=core`), and declares 4 CPUs and 8 GB; the harness checks that devcontainer features
  are pinned by digest.
- The local lab (docs/LOCAL_LAB.md), ported from tx01v2: the whole v1 platform on Docker, with no
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
    `scripts/leftovers-local.sh`; local contract `lab-system/lab-contract` (docs/CONTRACT.md).
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
  (docs/ARCHITECTURE.md, "v1 → v2"):
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
  - `app_deployer_principal_ids` get the same Azure roles as `dx02v2-gha-deploy` (repository-scoped
    Container Registry Repository Writer, Azure Kubernetes Service Cluster User Role, App
    Configuration Data Reader) besides the RoleBinding subject, with tests for a list of deployers
    and for an empty list.
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
    `docs/LESSONS_LEARNED.md` (sanitized lessons learned from the Azure v1 lab, December 2025 –
    January 2026).

### Changed (after the first push)

- The CI (`static`, `test`) ran green on GitHub: the README status matrix now says `verified in CI`
  for those rows; AGENTS.md and docs/MAINTENANCE.md follow.
- The README family table and AGENTS.md link the Google Cloud pair (`tx03v2`, `dx03v2`), now public.

## R10: capacidade e FinOps

- OpenCost/VPA Off, load/HPA/PDB and HA kind; optional budget/expiration and Spot. Heavy evidence runs in CI; nothing in v2 has run in the cloud.
