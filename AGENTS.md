# AGENTS.md

Instructions for AI coding agents and humans working in `tx02v2`. `CLAUDE.md` points here; this file
is the source of truth. The full rule list (pt-BR) is [docs/GUARDRAILS.md](docs/GUARDRAILS.md).

## 1. Mission and context

- `tx02v2` is the Azure infrastructure half of a public, educational DevOps lab (v2 family:
  `tx01v2` + `dx01v2` on AWS, `tx02v2` + `dx02v2` on Azure, `tx03v2` + `dx03v2` on Google Cloud).
- It must stay healthy without any cloud account: every claim is backed by the local harness or
  carries a status label (`verified in CI`, `verified locally`, `not run in the cloud (v2)`, `planned`).
- Current status: the harness (`HARNESS_STRICT=1 make verify`) passes locally in a Linux container
  (38 checks with the local lab) and in CI (jobs `static`, `test`; 32 checks before the local lab).
  **Nothing of v2 has run in Azure** (bootstrap, apply, plan, platform and destroy are
  `not run in the cloud (v2)`).
- The local lab ([docs/LAB_LOCAL.md](docs/LAB_LOCAL.md)) rebuilds the whole v1 platform on Docker:
  `terraform/envs/local` (kind + emulated ACR, PostgreSQL Flexible Server, Blob Storage through an S3
  API emulator, load balancer, git server) and `platform/local` (Istio ambient, cert-manager, ESO,
  Prometheus/Alertmanager/Grafana, Loki/Alloy, Tempo and the OpenTelemetry Collector, Argo CD,
  Gatekeeper, Trivy Operator, Velero, Chaos Mesh). `make e2e` proves it with 34 probes (CI job `e2e`). It is not cloud-mutating: agents may run it, one heavy run at a time (8 GB of Docker
  memory for `full`, 7 GB with `LOCAL_SIZE=small`).
- The interface with `dx02v2` is [docs/CONTRATO.md](docs/CONTRATO.md) (contract v2, owned here; the
  local lab has its own local contract, `lab-system/lab-contract`).

## 2. Non-negotiable rules

1. Never commit secrets or real identifiers (subscription, tenant, object and client IDs, resource
   IDs, the real name suffix, hostnames, public IPs, e-mails). Use
   `00000000-0000-0000-0000-000000000000` (or another GUID of one repeated hex digit),
   `tx02v2lab00000000`, `203.0.113.10/32`/`<YOUR_IP>/32`, `you@example.com`. The only real GUIDs
   allowed are built-in Azure role IDs listed by name in `BUILTIN_ROLE_IDS` of `scripts/harness.sh`;
   the Terraform code takes them from `terraform/modules/role-ids` (tests repeat them as expected
   values).
2. Never run cloud-mutating actions — `terraform apply`/`destroy` against Azure,
   `platform/install.sh`/`uninstall.sh`, `kubectl`/`helm` against a cloud cluster, `az` write
   commands, dispatching cloud workflows — unless a human explicitly asks for that action in the
   current task. Read-only `gh api` lookups and public HTTP GETs (docs, registries, the Azure Retail
   Prices API) are fine.
3. Never weaken a gate: no `continue-on-error`, no `|| true` on checks, no `--no-verify`, no disabled
   or skipped checks, no new scanner ignores without `statement` + `expired_at`.
4. Never widen Azure roles (including the ABAC role list of `modules/role-ids`), network, Kubernetes
   RBAC or CORS without stating why in the PR. Nothing is ever assigned at subscription scope.
5. Keep the contract: changes need coordinated PRs in `tx02v2` and `dx02v2` and a version bump.
6. Pin every new dependency, action, chart and image (version + SHA256, 40-char SHA + `# vX.Y.Z`,
   digest) and update the docs in the same change.
7. Once the ruleset is on, never push to `main`: pull requests only.

## 3. Repo map

```text
.github/workflows/      ci.yml (harness), terraform-plan/apply/destroy.yml, platform.yml (cloud: dispatch; plan also on PRs)
.github/rulesets/       main.json: branch ruleset applied by scripts/repo-guardrails.sh
.devcontainer/          Linux environment + Docker-in-Docker, pinned by digest (runs make tools; make e2e works inside)
docs/                   pt-BR docs: architecture, contract, runbook, costs, guardrails, harness, sustainment
FORK.md                 how to fork the lab: what GitHub does not copy, the local lab, your own cloud account
platform/               install.sh / uninstall.sh / render-manifests.sh, versions.env, Helm values, manifests
platform/local/         local platform: install.sh, check.sh (probes), uninstall.sh, versions.env, values/,
                        values/small/ (LOCAL_SIZE=small), manifests/, policies/ (Gatekeeper templates,
                        constraints, gator tests)
scripts/harness.sh      every check of the harness (stages static, test, e2e, all, list)
scripts/local-lab.sh    local lab: preflight | up | down | check | e2e | kubeconfig | status (LOCAL_PROFILE, LOCAL_SIZE)
scripts/leftovers-local.sh          fails when anything of the local lab survived the destroy
scripts/local/          kind-cluster.sh (called by terraform/envs/local)
scripts/install-tools.sh            pinned tools into .tools/ (SHA256-verified)
scripts/update-tool-checksums.sh    bump a tool: versions.env + checksums.txt from upstream checksums
scripts/leftovers.sh    read-only scan for billable/orphaned lab resources after a destroy
scripts/repo-guardrails.sh          repository settings via gh api (run by the maintainer, and once by every fork owner)
scripts/lib/            shared bash helpers (common, tools, azure, local)
terraform/bootstrap/    providers, state account, lab resource group, 3 GitHub identities + roles, budget
terraform/envs/lab/     lab root: modules, generated secrets, role assignments, contract keys
terraform/envs/local/   local lab root (Docker provider, local state outside the repo, kind-config.yaml)
terraform/modules/      network, aks, postgres, keyvault, acr, agc, appconfig, role-ids
terraform/tests/mocks/  shared mock data for terraform test
tools/                  versions.env and checksums.txt of the harness tools
```

## 4. Setup

- Linux or WSL 2 (Ubuntu) with bash >= 4.4, curl, unzip, xz, git, make: `make tools`.
- Windows/macOS: open the repo in the devcontainer (it runs `make tools`). macOS without the
  devcontainer: `brew install bash`.
- No cloud credentials are needed for anything except the cloud workflows,
  `platform/install.sh`, `platform/uninstall.sh` and `scripts/leftovers.sh` (Azure CLI login).
  `platform/render-manifests.sh` runs offline (the harness uses it).

## 5. Harness commands

| Command | Runs | When |
|---|---|---|
| `make tools` | `scripts/install-tools.sh` (all pinned tools) | first time, after a tool bump |
| `make static` | `scripts/harness.sh static`: policies, contract, fmt, validate, lock files, tflint, trivy (x2), actionlint, shellcheck, kubeconform, helm template, gitleaks | every change |
| `make test` | `scripts/harness.sh test`: `terraform test` for bootstrap, envs/lab (mocked azurerm) and envs/local (mocked docker, tls, random) | every Terraform change |
| `HARNESS_STRICT=1 make verify` | static + test with SKIP = FAIL (CI jobs `static` and `test`) | before every PR |
| `make e2e` | `scripts/harness.sh e2e`: the local lab end to end, always destroyed (CI job `e2e`) | `platform/local`, `terraform/envs/local` or tool changes |
| `make local-up` / `local-check` / `local-down` | keep the local lab running between steps (`LOCAL_PROFILE`) | debugging the platform |
| `scripts/harness.sh list` | lists all checks | any time |

## 6. Definition of Done

- [ ] `HARNESS_STRICT=1 make verify` green locally; CI green (`static`, `test`, `e2e`).
- [ ] Platform changes: a probe in `platform/local/check.sh` proves the new behaviour.
- [ ] Docs, README status matrix and `CHANGELOG.md` (`[Unreleased]`) updated in the same PR.
- [ ] No new unexplained scanner ignores; no weakened checks.
- [ ] Contract respected (or bumped with a linked `dx02v2` PR).
- [ ] New dependencies pinned; no secrets or real identifiers.

## 7. Playbooks

**Maintainer / sustentação.** Follow [docs/SUSTENTACAO.md](docs/SUSTENTACAO.md): react to a red
scheduled CI, merge monthly Dependabot PRs, run the quarterly review (tools, ALB Controller and ESO
charts and digests, AKS/Azure Linux/PostgreSQL calendar, kubeconform schema commits, prices in
`docs/CUSTOS.md`, ignores close to `expired_at`).

**Reviewer.** Check the PR template boxes; confirm the harness is green; look for widened Azure roles
(a new entry in `modules/role-ids` widens what the apply identity may assign), role assignments
outside `tx02v2-lab`, public access or local auth turned on, unpinned references, ignores without
justification, docs claiming more than the harness proves, and contract changes without a version
bump.

**Dependency updater.** One Dependabot group per PR. Read the release notes. Terraform providers:
keep the same constraint in every `versions.tf` (modules included), regenerate both lock files for
the four platforms and re-check what the provider refresh calls (docs/SUSTENTACAO.md 5.3 and 5.10).
Actions: confirm the new SHA matches the tag comment. Harness tools are bumped only with
`scripts/update-tool-checksums.sh`. ALB Controller bumps go together with `dx02v2` (its CRD schemas).

**Cloud operator** (only with explicit human approval for that action): read the cost section of the
README first (Application Gateway for Containers with the WAF is the biggest item), use a dedicated
subscription, follow [docs/RUNBOOK.md](docs/RUNBOOK.md), always finish with destroy +
`scripts/leftovers.sh` run locally as the subscription Owner, and file a `cloud_run_report` issue
with redacted identifiers. Never leave a lab running unattended.

## 8. Common tasks

- Add a Terraform input: variable in `terraform/envs/lab/variables.tf` with a validation, pass it to
  the module, add a test (positive and `expect_failures`), document it in `docs/RUNBOOK.md` and add
  the `TF_VAR_*` to the workflows if CI must pass it.
- Add a resource: `tags = local.tags` in a root or `tags = var.tags` in a module (`policy-tags` reads
  the provider schema); add a `mock_resource` default with a valid Azure resource ID to
  `terraform/tests/mocks/azurerm.tfmock.hcl`; assert inside the module with a run block
  `module { source = "../../modules/<name>" }`.
- Add a role assignment: only roles of `terraform/modules/role-ids`, scoped to `tx02v2-lab` or a
  resource inside it, in `terraform/envs/lab/roles.tf`. A new role there also changes the ABAC
  condition of `tx02v2-gha-apply` (re-apply the bootstrap) and needs its ID, with the same name, in
  `BUILTIN_ROLE_IDS` of `scripts/harness.sh` (`policy-identifiers` checks it). The tests prove that
  the ABAC list equals the roles the lab root assigns.
- Add a contract key: `terraform/envs/lab/contract.tf`, `CONTRACT_KEYS` in `scripts/harness.sh` and
  the table of `docs/CONTRATO.md`, plus a coordinated `dx02v2` PR and a version bump.
- Bump a harness tool: `scripts/update-tool-checksums.sh <tool> <version>`, then `make tools verify`.
- Bump the ALB Controller or External Secrets: docs/SUSTENTACAO.md 5.5 / 5.6 (chart, SHA256, image
  digests, CRDs).
- Add a check: docs/HARNESS.md ("Como adicionar um check").

## 9. When to stop and ask a human

- Any action that changes or costs money in a cloud account, or needs credentials.
- A check fails for a reason outside the repository (upstream outage, broken catalog, a chart
  archive whose SHA256 changed) — report it; do not weaken or skip the check.
- A contract change, an Azure role/RBAC/network widening, or a new scanner ignore.
- A change of defaults that moves the hourly cost (VM size, node count, WAF, logs).
- Rewriting git history, force-pushing, changing repository settings or rulesets.
- Anything that would make a README/doc claim stronger than the evidence.
