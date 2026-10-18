# tx02v2 maintenance

Maintain this repository without a cloud account: routines, support calendar and
step-by-step procedures. The original calendar below is a **2026-10-11 historical
snapshot**, with subsequent R4/R9 entries preserved. Check current official release
sources before choosing an upgrade; the table does not claim a new support audit.

## 1. Goal and scope

Covers Terraform, scripts, workflows, harness tools, platform versions (AKS,
Azure Linux, PostgreSQL, ALB Controller, External Secrets) and optional cloud
runs. Application maintenance lives in dx02v2; coordinated changes are listed here.

## 2. Current state

- Complete harness on main; current Actions/check list is authoritative.
  Historical snapshots recorded 32 CI checks, then 38 locally verified checks
  including the local lab; full-profile checks subsequently ran in Actions.
  These counts describe those revisions rather than a fixed current total.
- Local lab: verified in CI (e2e; historical 34 probes); verified locally on
  2026-10-13 (full, then 26 probes, no leftovers) and 2026-10-14
  (observability, traces and Slack).
- Bootstrap/apply/PR plan/platform/destroy: not run in the cloud (v2).
- dx02v2 contract: v5, 2026-10-17 (R9). The v3 snapshot dated 2026-10-16 added
  ambient/Gatekeeper, GitOps and Azure Velero; CONTRACT.md retains history.

## 3. Routines

| When | Task | Procedure |
|---|---|---|
| Weekly, automatic | Monday 06:00 UTC CI runs complete harness | Section6; common causes: expired ignore, changed URL/chart, network |
| Monthly | Dependabot action/provider/pre-commit PRs | AGENTS Dependency updater; one PR/group, green harness before merge |
| Quarterly | Harness tools, ALB/ESO charts/digests, platform versions, schemas, COSTS prices, expiring ignores, Dependabot ignore rules | Sections4–5; record CHANGELOG |
| Before cloud run | Read COSTS, budget, green commit CI, GitHub variables, quotas/SKU restrictions | RUNBOOK `1 |
| During cloud run | Record times/problems; never leave running overnight | RUNBOOK |
| After cloud run | Destroy, Owner-level local leftovers check, cloud_run_report, evidence-based status matrix | RUNBOOK sections 8–11 |

## 4. Support calendar (historical snapshot)

| Component | Version | End of support | Source | Action |
|---|---|---|---|---|
| AKS Kubernetes | 1.36, lab default; AKS GA 2026-06-30 | EOL2027-06-30; platform support until 1.40 GA; platform-initiated upgrade expected September 2027 | [AKS versions](https://learn.microsoft.com/azure/aks/supported-kubernetes-versions) | Upgrade1.37 before 2027-06-30 (section 5.4); patch channel stays1.36 |
| AKS Kubernetes | 1.37, AKS GA October 2026 | 2027-10-31 | Same | Next-quarter candidate after ALB/ESO/schema checks |
| Azure Linux nodes | 3.0, AzureLinux on AKS>=1.32 | About three years after 1.32, no exact date.2.0 unsupported since 2025-11-30; image removal from 2026-10-31 | [Support cycle](https://learn.microsoft.com/azure/azure-linux/aks-support-cycle) | Track3.0 end date/successor |
| PostgreSQL Flexible | 17 | Azure standard support through 2029-11-08, then paid Extended Support | [Version policy](https://learn.microsoft.com/azure/postgresql/configure-maintain/concepts-version-policy) | Major upgrade/contract+DX PR before date |
| Terraform | 1.16.5, >=1.11,<2 | No fixed date | [Releases](https://releases.hashicorp.com/terraform/) | Quarterly section 5.2 |
| azurerm | 5.9.0, ~>5.9 | No fixed date; major6 needs migration; Dependabot ignores majors | registry.terraform.io | Monthly section 5.3, reassess plan roles section 5.10 |
| random | 3.9.1, ~>3.9 | No fixed date | registry.terraform.io | Monthly |
| ALB Controller | 1.12.2, Gateway API1.5.1, minimum Kubernetes 1.32 | No published EOL; AKS add-on uses1.11.x with AKS 1.36+ | [Release notes](https://learn.microsoft.com/azure/application-gateway/for-containers/alb-controller-release-notes) | Quarterly section 5.5 with DX |
| ESO | 2.12.0/chart2.12.0, external-secrets.io/v1 | Recent versions maintained | [Releases](https://github.com/external-secrets/external-secrets/releases) | Quarterly section 5.6 with TX01 |
| kubelogin | 0.2.21,2026-10-09 | No published policy | [Releases](https://github.com/Azure/kubelogin/releases) | Quarterly section 5.1 |
| kubectl/Helm | 1.37.1/4.3.0 | kubectl ±1 API minor (1.36–1.38) | kubernetes.io,helm.sh | Follow cluster; Helm 4 uses rollback-on-failure instead of atomic |
| AKS ingress context | — | ingress-nginx retired2026-03-24; AKS NGINX routing supported until November 2026 | [AKS blog](https://blog.aks.azure.com/2025/11/13/ingress-nginx-update) | Keep AGC |
| azure/login | 3.1.0 | No published date | [Releases](https://github.com/Azure/login/releases) | Action Dependabot section 5.8 |
| PostgreSQL CA roots | DigiCert Global RootG2; Microsoft RSA/ECC RootCA2017 | 2038-01-15;2042-07-18 | [CA details](https://learn.microsoft.com/azure/security/fundamentals/azure-ca-details) | Root replacement changes contract |
| Runner/devcontainer | Ubuntu24.04 LTS | Standard support2029-04 | ubuntu.com | Replace before end |
| ClusterSecretStore schema | CRDs-catalog f3e4382,2026-06-02 | — | HARNESS.md | Quarterly section 5.7 |
| Trivy exceptions | Original two AZU-0012/0013 | 2027-04-30; later AZU-0010 expires 2027-04-16 | .trivyignore.yaml | Review before expiration section 5.9 |
| Local Istio | 1.31.1 | ~2027-02, six weeks after 1.33 | [Supported releases](https://istio.io/latest/docs/releases/supported-releases/) | Quarterly section 5.12 with TX01 |
| Other local charts | versions.env: cert-manager1.21.2,kube-prometheus-stack92.3.0,Loki 7.3.0,Alloy 1.13.1,Tempo 3.1.0,Collector 0.176.0,ArgoCD 10.10.3,Gatekeeper 3.23.1,Trivy 0.37.0,Velero 12.2.1,Chaos 2.8.4,metrics-server 3.14.0 | Each maintains recent releases | Official project releases | Quarterly section 5.12 with TX01 |
| Full cloud charts | full/charts.txt, local pins/cloud Collector/Kyverno 3.8.2; Azure Velero plugin1.14.4 pinned digest | Recent releases | Official releases | Quarterly section 5.13 with TX01 |
| Emulated services | registry 3.1.2,Versity 1.8.0,SoftServe 0.12.3,cloud-provider-kind0.12.0,PostgreSQL 17 | No fixed dates | terraform/envs/local/images.tf | Quarterly section 5.12 |
| kind/gator | 0.33.0,node1.36.4 /3.23.1 | No published policy | kind/Gatekeeper releases | Quarterly section 5.12; node follows AKS minor |

## 5. Procedures

### 5.1 Harness tools

Applies to terraform/tflint/azurerm ruleset/trivy/actionlint/shellcheck/kubeconform/
gitleaks/kubectl/helm/kubelogin/kind/gator.

```bash
scripts/update-tool-checksums.sh trivy 0.76.0 # official release checksums
make tools && HARNESS_STRICT=1 make verify
git diff tools/ .tflint.hcl
```

Read release notes first. The script reads exact-release published checksums for
linux_amd64/linux_arm64/darwin_arm64. Shellcheck publishes none, so it downloads
all three artifacts and calculates SHA256.

- Gitleaks: also update pre-commit rev to tag commit with frozen version comment;
  version-consistency compares both.
- azurerm ruleset: script also updates .tflint.hcl; require zero tflint issues
  and compatibility with azurerm5.
- Trivy: newer built-in rules can introduce findings; harness uses skip-check-update.
- kubectl: remain within one minor of the cluster.

### 5.2 Terraform CLI

Run update-tool-checksums.sh terraform <version>. Change required_version only
when minimum must rise, consistently in all versions.tf (version-consistency).

### 5.3 Providers and four-platform locks

1. Read CHANGELOG/major upgrade guide: v5 resource_provider_registrations,
   rbac_authorization_enabled, node_provisioning_profile, write-only arguments.
2. Keep identical constraints in roots and every module. Dependabot updates only
   roots; version-consistency also checks modules.
3. In terraform/bootstrap and terraform/envs/lab:
   ```bash
   terraform init -backend=false -upgrade
   terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64
   ```
4. Strict verify: at least four h1 hashes/provider, matching azurerm locks.
   policy-tags rereads schema; newly taggable types need tags.
5. Perform section 5.10 plan-role review.

### 5.4 Kubernetes

Changing kubernetes_version changes contract (version plus DX PR). First check AKS
notes, ALB minimum Kubernetes and ESO compatibility.

1. Update default/description in lab variables.tf.
2. Update K8S_SCHEMA_KUBERNETES_VERSION and a supporting K8S_SCHEMA_REF in harness;
   version-consistency compares minor versions.
3. Keep kubectl within one minor (section 5.1).
4. Coordinate DX schema/kind/kubectl minor (its MAINTENANCE.md).
5. Update local kind-config.yaml; local-versions checks minor (section 5.12).

### 5.5 ALB Controller, coordinated with dx02v2

1. Read [release notes](https://learn.microsoft.com/azure/application-gateway/for-containers/alb-controller-release-notes)
   and Helm upgrade guide for Gateway API/minimum Kubernetes/CRD changes.
2. Pull `helm pull oci://mcr.microsoft.com/application-lb/charts/alb-controller --version <version>`;
   SHA256 the archive and update ALB_CONTROLLER_CHART_VERSION/SHA256 in platform/versions.env.
3. The chart uses one tag for all three images without digest support. Inspect
   alb-controller/alb-controller-bootstrap/alb-controller-crds with
   `docker buildx imagetools inspect mcr.microsoft.com/application-lb/images/<image>:<version>`.
   Record index digest *_IMAGE_SHA256 and linux/amd64 *_IMAGE_AMD64_SHA256.
4. Match albController.image.tag to chart version; version-consistency checks.
5. Strict verify downloads/hash-checks/renders; contract-platform checks values/pins.
6. DX update-crd-schemas.sh <version> regenerates from CRD image. Check exact
   healthcheckpolicy/webapplicationfirewallpolicy plurals; changes require contract/paired PRs.
7. Recheck bring-your-own roles, federated credential name and alb-controller-sa;
   update ARCHITECTURE.md.

install.sh rejects unexpected archive hashes and running Pod image digests.

### 5.6 External Secrets, coordinated with tx01v2

Update ESO_CHART_VERSION and all three external-secrets.yaml image entries:
controller/webhook/cert-controller share one digest; version-consistency requires
v<version>@sha256 three times. Match TX01 release/digest. CRD API changes from
external-secrets.io/v1 require a contract version change.

### 5.6.1 OpenTelemetry Collector, cloud/local and tx01v2

Cloud/local share chart OTEL_COLLECTOR_CHART_VERSION and contrib image digest;
helm-template rejects differing digests. Read Collector notes for renamed
components such as otlp_grpc/k8s_attributes/azure_monitor/azure_auth. Update both
values digests and chart version/SHA256 in platform/versions.env (OTEL_COLLECTOR_CHART_*).
Run verify/e2e: local proves the pipeline, Azure exporter runs only in cloud.

### 5.7 Kubeconform schemas

Pinned K8S_SCHEMA_REF (yannh/kubernetes-json-schema) and CRD_SCHEMA_REF
(datreeio/CRDs-catalog) match TX01. Inspect upstream history:

```bash
gh api 'repos/datreeio/CRDs-catalog/commits?path=external-secrets.io/clustersecretstore_v1.json&per_page=3'
```

See ESO schema caveat in HARNESS.md.

### 5.8 Image/action digests

Devcontainer: docker buildx imagetools inspect mcr.microsoft.com/devcontainers/base:ubuntu-24.04.
For actions outside Dependabot, gh api repos/<o>/<r>/git/ref/tags/<tag>; if object.type
is tag, dereference git/tags/<sha>. Pin commit SHA with version comment and verify
commits/<sha> exists (v1 pinned nonexistent SHAs). One SHA/action across workflows.

### 5.9 Trivy exceptions

Before expired_at, reconsider every justification. If still necessary, renew for
at most about seven months with updated explanation; otherwise fix/remove.
trivyignore-policy rejects expired or excessively long exceptions.

### 5.10 Plan roles after an azurerm update

Plan uses -refresh=false; identity has Reader on lab/state read, no data calls
(ADR14). Confirm updated provider's nonrefresh plan still reads only state and
management data sources (azurerm_client_config/resource_group). A new data
source may need management Reader, never restore Key Vault Secrets User.
plan_identity_is_read_only rejects data roles.

### 5.11 Prices

Quarterly, repeat Retail Prices API queries
(`https://prices.azure.com/api/retail/prices?$filter=...`) per COSTS row,
update date/README totals and investigate AKS FreeTierInfrastructureCost meter.

### 5.12 Local charts/images/kind

Pins match TX01; coordinate both.

1. Read each chart release; helm pull with exact version/repository and save
   version/archive SHA256 in local/versions.env.
2. Update local values image digests using buildx imagetools inspect (index
   digest); helm-template-local rejects unpinned images.
3. Update GATOR_VERSION through checksum helper with GATEKEEPER_VERSION;
   local-versions requires equality.
4. Update emulated images.tf, all digest-pinned; kind-config node follows lab
   Kubernetes minor.
5. Run verify/e2e (or use required Actions e2e on PR); record CHANGELOG.

### 5.13 Full cloud and Azure Velero plugin

full/charts.txt reuses local versions/hashes/digests; Azure overlays live in
platform/values/full. Before updating, render every chart, check namespaces,
ServiceAccounts/digests and compare TX01 pins. GitOps branch/path/permission
changes require coordinated DX contract updates.

Kyverno 3.8.2 verifies promotion attestations fail-closed. On update, review
ImageValidatingPolicy CRD, federation and ACR ABAC read permission. Trivy has a
separate identity with the same dx02v2/api/web read scope. Never restore
registry-wide AcrPull/AcrPush.

Azure plugin velero-plugin-for-microsoft-azure1.14.4 is digest-pinned. Review
official release, Workload ID/useAAD, AZURE_RESOURCE_GROUP/storageAccountURI.
Helm proves configuration, not Blob access/restore. Retain container-scoped
Storage Blob Data Contributor and 35-day lifecycle.

## 6. Incident response

| Situation | First steps |
|---|---|
| Red CI | Read first FAIL and its log; fix code, never weaken gate. Reproduce strict verify |
| Vulnerability | Dependabot/advisory → PR; harness section 5.1, charts/images section 5.5/5.6; private reports SECURITY.md |
| Budget alert | Owner-level leftovers; destroy running lab; inspect Cost Management by meter |
| Exposed credential | No long-lived cloud GitHub secrets. Rotate leaked Key Vault values with db_password_version/admin_token_version and apply; review roles/federation. History rewriting is maintainer decision |
| Destroy leftovers | Follow script output/RUNBOOK `9 and record cloud_run_report |
| Soft-deleted reserved name | ARCHITECTURE.md: The soft-delete trap |

## 7. Cloud run records

Every run creates a cloud_run_report issue with date/region/offer/commits/steps/
duration/observed cost/problems/leftovers. README status changes only with evidence.

## 8. Owners

Maintainer @maringelix decides, merges and authorizes cloud runs. AI agents follow
AGENTS.md.
