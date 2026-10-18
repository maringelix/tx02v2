# tx02v2 harness

The harness is the set of checks proving this repository's claims without a cloud
account. It lives in `scripts/harness.sh`; Makefile and CI only invoke it. CI uses
`HARNESS_STRICT=1`. Two known differences before the first commit: Gitleaks reads
the working tree (CI reads full history), and executable bits are required only
for scripts already in the Git index. `scripts/harness.sh list` is the current
inventory; the original snapshot listed 45 static checks and three
`terraform-test:*` checks, with `tool-versions` also in test (48 unique checks in
`make verify`). `local-lab-e2e` is in `make e2e`, outside verify.

## Layers

| Layer | Check | Proves | Does not prove | Runs |
|---|---|---|---|---|
| Tools | `make tools` | Versions from `tools/versions.env`, verified SHA256; linux_amd64, linux_arm64, darwin_arm64 | — | Local, CI |
| Versions | `tool-versions` | PATH uses pinned versions; mismatches fail in strict mode | — | Local, CI |
| Structure and evidence | `repo-structure`, `version-consistency` | Required files, English status labels, no self-praise/emojis/v1 README links, README <=250 lines, CLAUDE.md, LF, executable Git index bits (warning for unindexed scripts), digest-pinned devcontainer, consistent versions | Documentation accuracy | Local, CI |
| Terraform policies | `policy-terraform`, `policy-tags` | No v1 regressions: write-only secrets, private PostgreSQL, Entra ID only, no kubernetes/helm/azuread providers, no Owner/User Access Administrator or subscription-wide roles, no perpetual `timestamp()` diffs; tags on every type accepting tags in the pinned provider schema | Author intent | Local, CI |
| Identifiers | `policy-identifiers` | No real GUIDs, IPs, emails or 12-digit IDs; `modules/role-ids` contains verified built-in role IDs | Identifiers outside these patterns | Local, CI |
| Workflows | `policy-workflows`, `actionlint` | SHA-pinned actions, permissions, OIDC/guards, `-lock=false` only for plan, masked people/address secrets, `-refresh=false` for plan, typed destroy confirmation and `scripts/destroy.sh`; YAML, expressions and run-block shellcheck | Azure runtime behavior | Local, CI |
| Scripts | `policy-scripts` | Environment variables cannot select the target (`RESOURCE_GROUP`, `CLUSTER_NAME`, `LAB_*`); temporary kubeconfig and kubelogin restricted to it; `require_lab_cluster` checks `Project=tx02v2`; `require_lab_context` protects local scripts | Azure runtime behavior | Local, CI |
| Offline flows | `destroy-flow`, `leftovers-flow`, `local-preflight` | Uninstall failure still reaches destroy/leftover checks; explicit subscription and only lab leftovers; local daemon consistency, no overlapping network/routes or occupied registry port; no actions on another LOCAL_STATE_DIR's lab | Actual Azure/Docker behavior; CLIs are simulated | Local, CI |
| Exceptions | `trivyignore-policy` | Every ignore has statement and expiration within about seven months | — | Local, CI |
| Contract | `contract-platform`, `contract-appconfig` | Core/full manifests, namespaces, labels, exact RBAC and subjects, ClusterSecretStore, GitOps, overlays/admission; invalid inputs rejected; 17 keys in contract.tf match harness and CONTRACT.md | Extra table rows or application implementation | Local, CI |
| Format and syntax | `terraform-fmt`, `terraform-validate:*` | Formatted HCL valid against pinned provider schema (three roots; original snapshot eight modules) | Azure accepts the values | Local, CI |
| Provider locks | `terraform-lockfiles` | At least four h1 hashes per provider in root lockfiles, generated for linux_amd64/linux_arm64/darwin_arm64/windows_amd64 | Which platform each hash belongs to | Local, CI |
| Lint | `tflint` | Recommended preset and azurerm 0.32.0 ruleset without findings | Rules requiring Azure calls | Local, CI |
| IaC security | `trivy-config`, `trivy-config-tfvars` | No HIGH/CRITICAL findings outside documented exceptions | Runtime configuration or effective RBAC | Local, CI |
| Bash | `shellcheck` | Style-level checks in scripts/ and platform/ | Azure runtime behavior | Local, CI |
| Manifests | `kubeconform` | Strict core/full manifests for Kubernetes 1.36, pinned ESO/known CRD schemas; admission check covers critical Kyverno fields | Admission/runtime behavior | Local, CI with network |
| Cloud charts | `helm-template`, `helm-template-full` | Core ALB Controller/ESO/Collector; 16 pinned/SHA256 cloud charts, overlays checked against real charts, digest images, internal Services, Trivy/Kyverno Workload ID, GitOps, rendered sizing compared with COSTS.md | Installation, Blob access or controller runtime | Local, CI with network |
| Admission/order | `image-admission-policy`, `full-install-order` | App images require digest/promotion attestation; waypoint/security/observability/policies/admission precede GitOps; uninstall deletes policy/PVCs | Real workflow signature or cluster admission | Local, CI |
| Secrets | `gitleaks` | No known secret pattern, full history after first commit, working tree beforehand | Secrets outside known patterns | Local, CI |
| Unit tests | `terraform-test:bootstrap`, `terraform-test:envs/lab` | Original snapshot 19/57 cases: OIDC subjects, state, plan/apply/deployer roles, ABAC allowlist, budget, AKS/nodes, password-free PostgreSQL state, Key Vault, ACR, AGC/WAF, Velero Blob/Workload ID, contract keys, Entra-only Insights, negative validation | Successful Azure provisioning; providers are mocked | Local, CI |
| Local Terraform | `terraform-validate:envs/local`, `terraform-test:envs/local` | Ten plan-only cases: private network, labels, only loopback registry port, TLS-only database, digest images, negative inputs | Docker creates containers; e2e covers that | Local, CI |
| Local/cloud policies | `local-versions`, `helm-template-local`, `policy-gator`, `platform-sizing`, `fork-references` | Pinned local charts, ClusterIP, small overlays, positive/negative Gatekeeper cases, Azure ACR/namespace constraints, summed rendered requests, fork GitOps URLs | Cluster runtime | Local, CI with network |
| Local end to end | `local-lab-e2e` (`make e2e`) | Apply local Terraform, install full platform, probes in `platform/local/check.sh`, always destroy/check leftovers; original snapshot 34 probes | Azure | Docker >=8 GB/CI; verified in CI; local full 2026-10-13 (then 26 probes), observability 2026-10-14 |
| Cloud | terraform/platform workflows | — | — | `not run in the cloud (v2)` |

## CI jobs

### Cloud readiness audit regressions

- `edge-acme` renders exact AGC/frontend pairs for primary and secondary and
  rejects mixed pairs, foreign names and invalid targets. The installer passes
  its target to the renderer; the test does not issue ACME certificates.
- `cloud-install` calls the real core-install/full-upgrade Collector functions,
  stubs external mutations, and uses Helm to merge each call's values/arguments.
  It requires the client ID annotation, Workload ID label and Azure exporter.
  `helm-template-full` checks these fields in the real pinned chart, independent
  of values retained by an earlier release.
- `image-admission-policy` converts the rendered policy with Helm fromYaml/JSON
  and validates it with jq: Kubernetes mode, namespace, Pod operations,
  repositories, workflow identity and Fail/Deny. JSON-mode and Audit-only
  mutants must fail. This proves the configuration regression, not an executed
  webhook or positive signature verification in AKS.

These light checks do not access Azure. Authentication, admission of signed and
rejected images, and TLS issuance/renewal remain cloud homologation evidence.

| ci.yml job | Target | Stage |
|---|---|---|
| static | `make tools && make static` | static |
| test | `make tools && make test` | test |
| e2e | `make tools && make e2e` | e2e; diagnostic artifact on failure |

IDs static/test/e2e are stable ruleset-required checks (e2e added 2026-10-13);
`policy-workflows` fails if any disappears. CI receives no Azure credentials.

## Strict mode

`HARNESS_STRICT=1`, set in CI/devcontainer, changes every SKIP to FAIL and requires
pinned PATH versions. Otherwise SKIP is allowed only for a missing local
prerequisite and always explains why.

`HARNESS_VERBOSE=1` shows passing-check output; `HARNESS_ONLY=<regex>` selects
checks for local debugging (for example `HARNESS_ONLY='^tflint$' scripts/harness.sh static`;
CI never uses it). `HARNESS_WORK_DIR` changes the data directory below.

## Add a check

1. Write `check_<name>` in scripts/harness.sh returning zero for PASS or nonzero
   for FAIL. Use `need <tool>` / `skip "<reason>"` only for missing prerequisites.
2. Register it in register_checks in the correct stage (static/test).
3. Run list and `HARNESS_STRICT=1 make verify`. Prove failure by applying the
   defect to a repository copy and requiring FAIL.
4. Update this table, GUARDRAILS.md if applicable, and CHANGELOG.

For a new tool, add official URLs to scripts/lib/tools.sh, a pin to
tools/versions.env, and run `scripts/update-tool-checksums.sh <tool> <version>`.
For another provider, update module/roots versions and regenerate root locks
for every supported platform.

## Host setup

- Linux: bash >=4.4, curl, unzip, xz, git, make; `make tools`.
- Windows: digest-pinned devcontainer or Ubuntu WSL 2. Git Bash is unsupported;
  installed harness tools target Linux/macOS.
- Apple Silicon macOS: `brew install bash` (system bash 3.2 is insufficient), or
  devcontainer. Tool installer supports linux_amd64, linux_arm64, darwin_arm64.
- Standalone container, as used for this repository's local verification:
  `docker run --rm -e HARNESS_STRICT=1 -v "$PWD:/work" -w /work ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl unzip git xz-utils make >/dev/null && make tools && make verify"`.
  Add `-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=*`
  if files belong to another user.

## Data outside the repository

Terraform data (`TF_DATA_DIR`), provider schema, logs and caches go to
`HARNESS_WORK_DIR` (default `$TMPDIR/tx02v2-harness`); the provider plugin cache
uses `TF_PLUGIN_CACHE_DIR` (default `~/.terraform.d/plugin-cache`, cached in CI).
Only .tools/ and ignored module lockfiles stay in the repository. `make clean`
removes .tools/, .cache/, .terraform directories, module locks and the default
HARNESS_WORK_DIR. Plugin cache and a custom HARNESS_WORK_DIR remain.

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| SKIP tool-versions: missing tools | Tools not installed | make tools |
| terraform-validate:envs/lab lock error | Provider changed without lock update | Run `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64` in root; MAINTENANCE.md section 5.3 |
| policy-tags: has no tags | New resource/type lacks tags | Root `tags = local.tags`; module `tags = var.tags` |
| contract-appconfig | Contract key differs across sources | Update contract.tf, CONTRACT_KEYS, CONTRACT.md and dx02v2 together |
| helm-template SHA256 | Chart archive changed upstream | Stop; review release before changing hash (MAINTENANCE.md section 5.5) |
| trivyignore-policy expired | Exception expired | Fix code or renew with a fresh explanation |
| kubeconform could not find schema | Network or uncompileable catalog schema | Check connectivity and note below |
| repo-structure not executable | Windows commit lost executable bit | `git update-index --chmod=+x <file>` |
| gitleaks | Secret or false positive | Remove/rotate secret; false positives require justified .gitleaksignore/PR. Before first commit, `gitleaks dir .` also scans ignored tfvars/backend.hcl/.env: store local credentials outside repository |
| policy-identifiers | Real GUID/email/IP | Use zero GUID, you@example.com or 203.0.113.10/32 |

Kubeconform note (checked in tx01v2 on 2026-10-10; same pin here): datreeio
CRDs-catalog revision 2026-10-08 (`b7e2015`, ESO 2.12) puts
`"additionalProperties": false` inside a properties map (crd provider);
kubeconform cannot compile it. The harness pins prior `f3e4382` (2026-06-02),
which strictly validates this ClusterSecretStore, including rejecting misspelled
fields. Revisit quarterly (MAINTENANCE.md section 5.7).

## R10: capacity and FinOps

See [FinOps and scaling](FINOPS.md) for HA kind, load/HPA/PDB, OpenCost, VPA Off,
opt-in Spot, regional rates, budget/expiration and cleanup. Built for forks;
nothing in v2 has run in the cloud.
