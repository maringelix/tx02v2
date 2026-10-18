# tx02v2 guardrails

A guardrail is a rule plus its enforcement, automated where possible. This
document lists rules, enforcement and limits. Types: blocking (fails harness,
CI or apply), alert (notification), process (human/agent discipline). Tests
live under terraform/*/tests/ and run with make test. Stable rule IDs remain
unchanged when prose is translated.

## Rules

| ID | Rule | Reason | Enforcement | Type |
|---|---|---|---|---|
| SEC-01 | No repository secrets | Public history persists | gitleaks harness/pre-commit | blocking |
| SEC-02 | No real identifiers: GUIDs only repeated-digit placeholders or named built-in role IDs, example.com emails, private/RFC5737 IPs | Avoid exposing subscriptions/tenants/people | policy-identifiers | blocking |
| SEC-03 | Ephemeral secrets and write-only administrator_password_wo/value_wo; no cloud random_password/random_string resources | No values in plan/state | policy-terraform; postgres_password_never_in_plan_or_state, key_vault_and_secrets | blocking |
| SEC-04 | GitHub federation uses exact immutable owner/repo numeric-ID subject, GitHub issuer, api://AzureADTokenExchange; apply/deploy only lab environment, deployment only DX02 | No static secrets, foreign repos/branches/environments or re-registered account inheritance | identities_follow_the_contract; repo-guardrails verifies subject | blocking |
| SEC-05 | id-token:write only cloud jobs with lab environment, guarded plan exception; never ci.yml; no client-secret/creds/storage keys | Limit credential acquisition | policy-workflows | blocking |
| SEC-06 | Authorized AKS API ranges; 0.0.0.0/0 requires allow_api_server_from_anywhere=true | Explicit exposure decision | validations/aks tests | blocking |
| SEC-07 | CI roles only lab group/state container, no subscription scope, Owner or User Access Administrator | Cannot reach other subscription work | bootstrap roles tests, policy-terraform | blocking |
| SEC-08 | Apply ABAC permits only 11 role-ids built-ins, lab assigns exactly needed roles; repository-specific ACR conditions | No apply self-escalation; kubelet/Trivy/Kyverno read only app repos, deployers write only them, Velero only its container | apply_identity_is_scoped_to_the_lab, the_lab_assigns_exactly_the_abac_roles, no_app_deployers_assign_nothing_extra | blocking |
| SEC-09 | Entra only: no AKS local accounts, Azure RBAC, no ACR admin/anonymous pull, no App Configuration local auth/storage shared keys; Key Vault RBAC | No static cloud credentials | policy-terraform, AKS/data_stores tests | blocking |
| SEC-10 | Private PostgreSQL, no public access/firewall rules, TLS>=1.2; 5432 only node subnet | No Internet database port | postgres_server, postgres_is_reachable_only_from_the_aks_nodes, policy-terraform | blocking |
| SEC-11 | No deployer Key Vault roles; ESO Secrets User only on lab vault | Least secret privilege | the_lab_assigns_exactly_the_abac_roles | blocking |
| SEC-12 | Plan PR only from same repository and configured AZURE_PLAN_CLIENT_ID | Forks receive no credentials | terraform-plan.yml, policy-workflows | blocking |
| SEC-13 | Required github_owner rejects your-github-user; budget email rejects you@example.com | Fork must trust its own repos and a monitored recipient | Variable validation, placeholder_owner_is_refused, placeholder_alert_email_is_refused, FORK.md | blocking |
| SEC-15 | Operator ranges/admin/deployer lists are LAB_API_SERVER_AUTHORIZED_IP_RANGES/LAB_CLUSTER_ADMIN_PRINCIPAL_IDS/LAB_APP_DEPLOYER_PRINCIPAL_IDS secrets; workflows mask every element; summaries/artifacts replace GUID/CIDR/IP | Public logs must not expose home IP/object ID | policy-workflows | blocking |
| SEC-14 | Scripts target contract lab and verify Project tag; RESOURCE_GROUP/CLUSTER_NAME cannot redirect. Temporary kubeconfig only, kubelogin only that file, no current-context changes. Local scripts require kind-tx02v2-local. Global PostgreSQL name has subscription suffix | Fork machine/subscription can contain unrelated clusters/env vars/labs | policy-scripts, require_lab_cluster in azure.sh, require_lab_context in local.sh, defaults_are_lab_friendly | blocking |
| SUP-01 | Harness versions/SHA256 pinned; mismatch fatal | Supply chain | install-tools.sh, checksums.txt, tool-versions | blocking |
| SUP-02 | Every action40-character SHA + version comment, one SHA/action | Mutable tags | policy-workflows, version-consistency | blocking |
| SUP-03 | Root provider locks for four platforms, >=4 h1 hashes; init readonly | Reproducibility | terraform-lockfiles, terraform-validate:* | blocking |
| SUP-04 | ALB chart SHA256 and running image digests checked; ESO/devcontainer digest-pinned | Changes require diff | helm-template, contract-platform, version-consistency, repo-structure, install.sh | blocking |
| SUP-05 | Trivy only via install-tools, never trivy-action/setup-trivy, GHSA-69fq-xp46-6x23 | March 2026 supply-chain incident | policy-workflows | blocking |
| SUP-06 | Consistent ruleset/hook/ALB tag/ESO digest/Terraform/azurerm/schema Kubernetes minor | Complete upgrades | version-consistency | blocking |
| SUP-07 | Monthly Dependabot, grouped minor/patch, separate majors; azurerm major/Gitleaks hook intentionally ignored with comments | No silent decay | dependabot.yml | alert |
| IAC-01 | No Kubernetes/Helm/azuread providers | Separate cluster/directory boundaries; v1 lesson | policy-terraform | blocking |
| IAC-02 | Bootstrap provider resource_providers_to_register, never registration resource; registrations=none/storage_use_azuread=true, no provider/backend credentials | Avoid MissingSubscriptionRegistration/use_cli v1 errors | policy-terraform, resource_providers_of_the_lab_are_registered; provider wiring reviewed | blocking |
| IAC-03 | local.tags/var.tags on every schema-supported type, contract values | azurerm lacks defaults; leftovers uses Project tag | policy-tags, defaults_are_lab_friendly/module tests | blocking |
| IAC-04 | timestamp/plantimestamp only with lifecycle ignore_changes for attribute | Avoid perpetual diff | policy-terraform | blocking |
| IAC-05 | Validate nonboolean inputs: canonical/nonoverlapping CIDRs, exact AGC/24, lowercase GUIDs, Kubernetes minor, non-B-series VM, node counts | Fail before Azure call | validations.tftest.hcl, historical 31 cases | blocking |
| IAC-06 | No HIGH/CRITICAL Trivy config findings, including example tfvars | IaC security | trivy-config, trivy-config-tfvars | blocking |
| IAC-07 | Zero recommended/azurerm tflint issues; inline ignores require reviewed reason | IaC quality | tflint, PR review | blocking |
| IAC-08 | Formatted/valid HCL in roots/modules | Readable review | terraform-fmt/validate | blocking |
| IAC-09 | No Azure Policy add-on | Cost and v1 Gatekeeper conflict | policy-terraform, control_plane | blocking |
| IAC-10 | Explain Azure role/network/RBAC/CORS widening in PR | Deliberate review | PR template | process |
| K8S-01 | Strict kubeconform, commit-pinned schemas | Invalid manifest blocked | kubeconform | blocking |
| K8S-02 | Restricted namespace, exact contract Role/ALB1.12.2 plurals, User/object-ID RoleBinding, azurekv WorkloadIdentity store only DX02; renderer rejects invalid inputs | Cluster least privilege | contract-platform | blocking |
| K8S-03 | ALB azure-alb-system/Gateway API/SecurityPolicy, clientID only set-string; ESO external-secrets SA, workload label, three digest images | Federation relies on names | contract-platform, helm-template | blocking |
| K8S-04 | Uninstall deletes/waits Gateways/routes/ALB policies/LB Services before destroy, failures visible | No Kubernetes-owned Azure leftovers | destroy order, policy-workflows | blocking |
| APP-01 | Versioned DX contract:17 contract.tf/harness keys equal, each documented; coordinated PRs | Publisher/consumer evolve together | contract-appconfig, contract_keys_in_app_configuration | blocking |
| APP-02 | Deploy identity/humans receive Writer only dx02v2/api/web, AKS Cluster User, App Configuration Reader | Equal access without extra privilege | app_deployers_get_the_roles_of_the_deploy_identity | blocking |
| CUSTO-01 | Budget25 billing units; Actual 50/80/100%, Forecasted 100%; required validated emails | Operator pays | bootstrap/budget.tf, budget.tftest.hcl | alert |
| CUSTO-02 | Economical core: AKS Free, two D2als_v6/autoscaler1–3, B1ms32GB/seven-day backup/noHA, Standard ACR ABAC, Free App Configuration, control-plane logs off | Minimum compatible with taught access/admission | defaults_are_lab_friendly, module tests | blocking |
| CUSTO-03 | Destroy never swallows errors; Terraform still runs after uninstall failure; always leftovers | Failed uninstall must not leave charging resources | destroy.sh/workflow, simulated destroy-flow, policy-workflows | blocking |
| CUSTO-04 | Same-day destroy, local Owner leftover check, cloud_run_report | Avoid forgotten cost | RUNBOOK | process |
| CI-01 | Jobs call harness through make targets | Same local/CI checks | PR review, ci.yml | process |
| CI-02 | No continue-on-error/swallowed true/echo/:, no sed on Terraform | Honest gates; v1 lesson | policy-workflows | blocking |
| CI-03 | Top contents:read, timeout/concurrency/ubuntu24.04/persist-credentials:false | Least privilege/predictability | policy-workflows | blocking |
| CI-04 | Strict mode turns every SKIP into FAIL | No silent omissions | ci.yml/harness | blocking |
| CI-05 | Cloud manual workflows, guarded PR plan; lab environment except plan; first Check step validates vars, OIDC-only, typed destroy confirmation | Costly actions require intent | policy-workflows checks step existence; content reviewed | blocking |
| CI-06 | Read-only plan -lock=false; apply/destroy retain lock | Plan cannot acquire write lease | policy-workflows | blocking |
| CI-07 | Plan summary/artifact/apply summary replace GUID/suffix; workflows mask tenant/subscription/client/deploy/suffix | Public workflow logs | plan/apply workflows | process |
| CI-08 | Monday06:00UTC scheduled CI | Detect expired ignores/chart/URL changes | ci.yml | alert |
| CI-09 | Required e2e each PR | Real local platform evidence | ci.yml/ruleset | blocking |
| LOC-01 | No cloud provider/remote backend in local root; Docker local socket only; random_password only disposable local state | Free local run | policy-terraform/docker_host validation | blocking |
| LOC-02 | All local containers label tx02v2.lab=local; only registry 127.0.0.1:5002 exposed; no privileged containers | Avoid exposure/leftovers | local tests/policy/leftovers | blocking |
| LOC-03 | Version/SHA256 charts, digest images, ClusterIP except runtime Gateways | Supply chain, no public Grafana/Argo UI | helm-template-local/local-versions/install hash rejection | blocking |
| LOC-04 | Gatekeeper deny, app webhook Fail, positive/negative cases per policy | v1 dryrun lacked audit | policy-gator/e2e policies | blocking |
| LOC-06 | Preflight same CLI/provider daemon, no network/route overlap or registry-port collision; act only on own LOCAL_STATE_DIR; clean only under Makefile directory | Fork machine may have VPN/unrelated containers/labs | local-preflight fake docker/kind/ip, preflight/require_own_lab, Makefile | blocking |
| LOC-05 | Actual traffic/API probe per component, always destroy/check leftovers | Claims require evidence | check.sh/local-lab.sh e2e | blocking in e2e |
| MUD-01 | Main ruleset requires PR, strict static/test, no force push | Every change through harness | ruleset/repo-guardrails/policy-workflows contexts | blocking after publication |
| MUD-02 | Scanner ignore needs statement/expired_at <=about seven months | Reviewed exceptions | trivyignore-policy | blocking |
| MUD-03 | Entry scripts executable in Git index | Windows loses bit | repo-structure; before first commit warning with git add --chmod=+x | blocking after first commit |
| MUD-04 | Conventional Commits, one topic/PR, Unreleased changelog | Readable history | CONTRIBUTING/PR template | process |
| DOC-01 | Exact evidence/status labels; no self-praise/emojis/v1 README links, <=250 README lines, LF | Honest documentation | repo-structure/review | blocking |
| DOC-02 | Docs change with code; public prose stays English | Prevent stale onboarding | PR template/review | process |
| AGT-01 | No cloud mutation without explicit human instruction for task | Money/security | AGENTS | process |
| AGT-02 | Never weaken gates or add unjustified/unexpired ignores | Trustworthy harness | AGENTS/checks | process |
| AGT-03 | Stop/ask in listed AGENTS cases, respecting existing authorization | Human control over costly decisions | AGENTS | process |
| K8S-05 | Full Argo ClusterIP; platform project, constrained app repository/namespace/kinds; get/watch/patch only dx02v2 Application | GitOps grants no other app access | Helm/contract/teardown tests | blocking |
| SEC-20 | Velero Workload ID, shared keys off, Deny firewall only own AKS subnets/bothDR, private Blob/container-scoped Contributor,35days, backup-prefix lifecycle/Kopia referenced GC | No static credential/broad data access | lab roles/network tests, helm-template-full | blocking |
| SEC-21 | Digest plus fork deploy-azure Sigstore promotion, ImageValidatingPolicy Fail/Deny | Unpromoted app image blocked | image-admission-policy/Helm/DX CI | blocking |
| K8S-06 | Full waypoint L7 with mesh mTLS, AGC HTTP exception only delegated subnet | Cannot bypass L7/open other services | contract/Helm/DX CI | blocking |

## Exceptions

A scanner exception requires:

1. Fixing the cause if feasible; otherwise explaining exact finding, need,
   risk and mitigation.
2. Adding statement and expired_at in .trivyignore.yaml, at most about seven months.
3. Explaining the exception in the PR. trivyignore-policy rejects absent/expired/
   excessive validity; Trivy stops applying expired entries.

Checked 2026-10-16: AZU-0010 (no AzureServices bypass because no service needs it,
expires 2027-04-16); AZU-0012 state public endpoint and AZU-0013 Key Vault public
endpoint for dynamic-IP hosted runners (ADR20, expire2027-04-30).
Accepted MEDIUM/LOW findings do not fail scan: purge protection off AZU-0016,
secrets without expiry AZU-0017, PostgreSQL logging AZU-0019/0021/0024, optional
AKS Monitor AZU-0040, state logging/geo replication AZU-0057/0058, platform keys
AZU-0060/0067 (ADR21), public cluster AZU-0065 (ADR19), no Azure Policy
AZU-0066 (IAC-09).

## Limits

- No Azure v2 run. Mock azurerm tests prove configuration, not accepted API
  calls or integrated resource behavior.
- Apply is powerful within lab (Contributor, Key Vault/App Configuration data
  roles and ABAC role assignment). Use dedicated subscription, required lab
  reviewer, main-only deployment.
- Plan reads lab/state without data-plane access; -refresh=false compares last
  state rather than drift (ADR14). Same-repo branch authors can change PR plan
  but reach only Reader/state scope. Forks receive no credential.
- Subscription/tenant/client IDs are workflow inputs. Azure does not treat
  them as secrets; masking/redaction is applied, but use a dedicated subscription.
- Repository LAB_*/AZURE_* variables appear in logs; private operator lists
  belong in secrets (SEC-15).
- Hosted-runner learning path allows API0.0.0.0/0; Entra/RBAC remain mandatory.
- ALB chart cannot pin image digests. Install checks chart hash first, running
  images afterward; an unexpected image already ran when failure requests removal.
- Budget alerts do not stop resources.
- Leftovers covers lab resource types. Apply identity sees only permitted
  resources; subscription listings may silently return lab scope, while wholly
  inaccessible checks report UNCHECKED. Complete check runs locally as Owner.
- ALB Reader on node resource group is intentionally absent (ARCHITECTURE).
- ClusterSecretStore schema is from 2026-06-02 (HARNESS).
- Free App Configuration has1,000 requests/day, then429 until midnightUTC.
- Local kind evidence does not prove Azure. cloud-provider-kind needs Docker
  socket; use disposable host/CI. Full local e2e is required CI evidence.
- istio-system/monitoring-agents/chaos-mesh need privileged Pod Security.
  Gatekeeper excludes platform namespaces to permit recovery while it is down.

## Verification

```bash
make tools                 # pinned binaries in .tools/
HARNESS_STRICT=1 make verify
scripts/harness.sh list    # checks and stages
scripts/leftovers.sh       # after destroy, az login as subscription Owner
```
