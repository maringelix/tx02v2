# Runbook: one complete cloud exercise

Start with the [family getting-started guide](https://github.com/maringelix/tx00v2/blob/main/docs/GETTING_STARTED.md).
This runbook provisions your Azure lab, publishes dx02v2, tears resources down and records results.
None of this has run in Azure v2 (`not run in the cloud (v2)`); your run supplies the first evidence.
Durations below are estimates, not measurements.

> **Cost:** defaults were about US$0.51/hour in eastus2, US$0.39 without WAF.
> AGC/WAF was the largest item, US$0.279/hour (Azure Retail Prices API, 2026-10-11).
> Check current official pricing and COSTS.md. Three hours were about US$1.50;
> a forgotten lab exceeds US$12/day. Destroy the same day.
>
> The historical full estimate with Standard_D2as_v5 was US$0.524/hour with WAF,
> US$0.400 without, approximately US$1.57/US$1.20 per three hours.
> Core retains Standard_D2als_v6. Full has not run in Azure; COSTS.md records requests,
> assumptions and variable storage/telemetry charges.

## 1. Prerequisites

- A **dedicated subscription**: the budget covers the subscription and leftovers.sh inventories
  its public IPs, load balancers, disks, AGC and PostgreSQL.
- Subscription **Owner** for bootstrap provider registration, resource groups and role assignments.
- **Free Trial historical findings** (January 2026, LESSONS_LEARNED.md section 1):
  Flexible Server was blocked in every tested region (LocationIsOfferRestricted); AKS VM sizes
  were rejected by offer/region; low quotas could not be increased on Free Trial.
  Pay-as-you-go upgrade removed those offer restrictions while retaining credit until 30 days
  after signup. Recheck current offer terms; a budget only alerts, never caps charges.
- SKU/quota checks:
  `az vm list-skus --location eastus2 --size Standard_D2als_v6 --all --output table`
  (empty Restrictions), `az vm list-usage --location eastus2 --output table`
  (four family vCPUs, six during upgrades). App Configuration Free allows up to three stores
  per subscription/region.
- Azure CLI, authenticated gh, and `make tools` (terraform, kubectl, helm, kubelogin).
  dx02v2 deploy also needs Docker; see its runbook.
- Public tx02v2/dx02v2 forks with Actions enabled and repo-guardrails.sh applied to each;
  environment lab has a required reviewer and main-only deployment (PUBLISHING.md).
  Apply/deploy federation trusts their exact lab subjects; plan uses its separate PR/main subjects.
- Estimated times: bootstrap ~5 minutes; apply ~30–45; platform ~10; app deploy ~15;
  destroy ~30–45. Allow 2–3 hours for a complete exercise.

## 2. Bootstrap, once locally as Owner

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # subscription_id, budget_alert_emails, github_owner, three IDs
terraform init
terraform apply
terraform output -raw backend_hcl > ../envs/lab/backend.hcl
terraform output github_variables_tx02v2       # section 3
terraform output github_variables_dx02v2       # section 3
```

Bootstrap registers lab providers, creates tx02v2-bootstrap and tx02v2-lab resource groups,
state account tx02v2tfstate<suffix>/container tfstate with CanNotDelete lock, federated identities
tx02v2-gha-plan/tx02v2-gha-apply/dx02v2-gha-deploy and contract roles, and monthly budget.
Default budget is 25 in billing currency; actual alerts at 50/80/100%, forecast at 100%.

- github_owner has no default: use the owner of both forks. The example your-github-user and
  you@example.com placeholders are refused.
- Federation pins GitHub's **immutable** sub with numeric owner/repository IDs:
  `repo:<owner>@<owner-id>/tx02v2@<repository-id>:environment:lab`.
  Repositories created after 2026-07-15, including new forks, emit this format. Name-only subjects
  do not match and could transfer trust to a re-registered deleted name.
  Get IDs with `gh api users/<owner> --jq .id`,
  `gh api repos/<owner>/tx02v2 --jq .id` and `gh api repos/<owner>/dx02v2 --jq .id`;
  fill github_owner_id/tx02v2_repository_id/dx02v2_repository_id. repo-guardrails.sh prints them too.
- Older repositories must opt into immutable claims (Settings > Actions > General > OpenID Connect).
  Check `gh api repos/<owner>/tx02v2/actions/oidc/customization/sub`:
  sub_claim_prefix includes @<id>. Renaming/transferring a repository changes sub; reapply bootstrap.
- Bootstrap state stays **local**, git-ignored terraform.tfstate. Back it up.
- Provider registration can take several minutes.
- **Owner data-plane trap:** Owner lacks data actions and state disallows shared keys.
  Bootstrap grants its operator Storage Blob Data Contributor on the container. Propagation takes
  minutes; if lab init immediately gives403 AuthorizationPermissionMismatch, wait and retry.
- Optional remote bootstrap state: create ignored terraform/bootstrap/backend_override.tf below,
  then run
  `terraform init -migrate-state -backend-config=../envs/lab/backend.hcl -backend-config="container_name=tfstate" -backend-config="key=bootstrap/terraform.tfstate"`.
  Harness reads every Terraform .tf: retain use_azuread_auth=true. Before final teardown,
  delete the override and `terraform init -migrate-state` back to local.

```hcl
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
```

## 3. GitHub variables and secrets

HA/DR and isolated restore are in [CONTINUITY.md](CONTINUITY.md).
Plan/apply/destroy accept LAB_POSTGRES_PROFILE=core|ha|dr (core default),
LAB_POSTGRES_HA_SKU (default GP_Standard_D2ads_v5),
LAB_POSTGRES_BACKUP_RETENTION_DAYS (7–35), LAB_POSTGRES_GEO_BACKUP (creation-time choice), and
LAB_POSTGRES_DELETE_LOCK (requires lock permissions; CI Contributor gains none).

DR defaults pair eastus2 with LAB_DR_LOCATION=centralus.
LAB_DR_VNET_CIDR, LAB_DR_AKS_NODES_SUBNET_CIDR, LAB_DR_AGC_SUBNET_CIDR,
LAB_DR_POSTGRES_SUBNET_CIDR, LAB_DR_POD_CIDR, LAB_DR_SERVICE_CIDR and LAB_DR_DNS_SERVICE_IP
default respectively to10.21.0.0/16,10.21.0.0/22,10.21.4.0/24,10.21.5.0/24,10.245.0.0/16,
10.1.0.0/16 and10.1.0.10. Terraform rejects within/across-cluster overlap.
Keep identical inputs through destroy. Changing geo backup can recreate PostgreSQL;
review plan/backups before altering an existing server.

Use **repository** variables under Settings > Secrets and variables > Actions:
plan runs without an environment. Public variables/logs must contain no private values.
Operator person/address lists are **secrets**, masked element by element.
Workflows validate formats, mask tenant/subscription/client/deployer/suffix identifiers in logs,
and replace GUIDs/addresses in summaries with <GUID>/<CIDR>/<IP>.

FORK.md step7 imports bootstrap github_variables_tx02v2/github_variables_dx02v2 with
gh variable set -f, and github_secrets_tx02v2 with gh secret set -f. Add chosen LAB_* values.

### tx02v2 repository

| Name | Example | Used by / source |
|---|---|---|
| AZURE_TENANT_ID | 00000000-0000-0000-0000-000000000000 | all cloud workflows; github_variables_tx02v2 |
| AZURE_SUBSCRIPTION_ID | 00000000-0000-0000-0000-000000000000 | all cloud workflows; same output |
| AZURE_PLAN_CLIENT_ID | 00000000-0000-0000-0000-000000000000 | plan, enables its guard; plan_client_id |
| AZURE_APPLY_CLIENT_ID | 00000000-0000-0000-0000-000000000000 | apply/platform/destroy; apply_client_id |
| TF_STATE_STORAGE_ACCOUNT | tx02v2tfstate00000000 | plan/apply/destroy; state_storage_account_name |
| LAB_LOCATION | eastus2 | TF_VAR_location; must match bootstrap |
| LAB_DEPLOY_PRINCIPAL_ID | 00000000-0000-0000-0000-000000000000 | plan/apply/destroy TF_VAR_deploy_principal_id; deploy_principal_id |
| LAB_CLUSTER_ADMIN_PRINCIPAL_IDS **secret** | ["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"] | JSON TF_VAR_cluster_admin_principal_ids; bootstrap secret initially contains apply_principal_id for platform/destroy; add operator object ID from az ad signed-in-user show --query id -o tsv |
| LAB_API_SERVER_AUTHORIZED_IP_RANGES **secret** | ["0.0.0.0/0"] | JSON TF_VAR_api_server_authorized_ip_ranges; hosted runners have dynamic IPs |
| LAB_ALLOW_API_SERVER_FROM_ANYWHERE | true | explicit opt-in for0.0.0.0/0; default false |
| LAB_APP_DEPLOYER_PRINCIPAL_IDS **secret** | [] | optional laptop-deployer object IDs; Terraform roles and platform RoleBinding; default[] |
| LAB_ENABLE_WAF | true | TF_VAR_enable_waf; defaulttrue; COSTS.md |
| LAB_DNS_ZONE_NAME | example.com | full requires this/app hostname/contact; Terraform creates lab public zone |
| LAB_APP_DOMAIN_NAME | lab.example.com | subdomain; CNAME targets AGC frontend |
| LAB_ACME_CONTACT_EMAIL | you@example.com | public ACME account contact; do not depend on expiry email notifications |
| LAB_NODE_VM_SIZE | Standard_D2as_v5 | plan/apply/destroy; core default Standard_D2als_v6; use D2as_v5 for full |
| LAB_NODE_COUNT | 2 | plan/apply/destroy;1–3, default2; preserve through destroy |
| LAB_SLACK_WEBHOOK_URL **secret** | incoming webhook URL | optional full-platform Slack; cluster Secret, never committed values |
| LAB_VELERO_REPOSITORY_PASSWORD **secret** | 64 random hexadecimal characters | full backup escrow; same private value across DR clusters, preserved outside regions; CONTINUITY.md |
| LAB_FINOPS_PRICING_JSON | reviewed JSON, no identifiers | mandatory plan/apply estimate gate; correct cloud/region/current rates; FINOPS.md |
| LAB_COST_BUDGET_USD | positive budget | plan/apply estimate ceiling; does not cap actual billing |
| LAB_COST_HOURS | duration <=24 | must cover expiry |
| LAB_COST_EXPIRES_AT | UTC within next24hours | refresh each run; expired gate blocks new plan/apply, not auto-destroy |
| LAB_ENABLE_SPOT_POOL | false | optional Spot user pool |
| LAB_SPOT_MAX_PRICE | 0.1 | operator bid ceiling; not a real rate guarantee |

TF_VAR_github_owner comes from github.repository_owner. Remaining defaults are in
terraform/envs/lab/variables.tf. With0.0.0.0/0 the API is reachable from any address during the
exercise, but Entra authentication and RBAC remain mandatory (ARCHITECTURE.md, ADR19).
The pricing worksheet, external allowances, maximum capacity and deadline rules are in
[FINOPS.md](FINOPS.md). Do not reuse the local simulated rates.

### dx02v2 repository

| Variable | Example | Source |
|---|---|---|
| AZURE_CLIENT_ID | 00000000-0000-0000-0000-000000000000 | dx02v2-gha-deploy client ID, github_variables_dx02v2 |
| AZURE_TENANT_ID | 00000000-0000-0000-0000-000000000000 | same output |
| AZURE_SUBSCRIPTION_ID | 00000000-0000-0000-0000-000000000000 | same output |
| AZURE_APPCONFIG_ENDPOINT | https://tx02v2-lab-00000000.azconfig.io | same output; store exists after apply, lab appconfig_endpoint |
| AZURE_DR_APPCONFIG_ENDPOINT | https://tx02v2-lab-00000000-dr.azconfig.io | DR only, lab dr_appconfig_endpoint |

Deploy runs in DX's own lab environment, trusting
`repo:<owner>@<owner-id>/dx02v2@<repository-id>:environment:lab`.

## 4. Apply

1. Run terraform-plan from main, or a same-repository Terraform PR. Review the sanitized summary.
   Plan uses no lab environment approval.
2. Run terraform-apply and approve lab. It saves a fresh plan, checks reviewed pricing/budget/expiry,
   applies that exact plan and reports outputs.

For full, configure all three DNS variables before apply. Delegate dns_name_servers at your
registrar afterward; wait for LAB_APP_DOMAIN_NAME to resolve through CNAME to agc_frontend_fqdn.
Terraform creates zone/record, not domain registration/delegation. Without delegation ACME fails.
Core leaves the three variables empty and teaches HTTP.

Local alternative with your identity: Owner lacks the data roles used by apply
(ARCHITECTURE.md, Owner data access). Grant them on the lab group; remove during teardown:

```bash
me="$(az ad signed-in-user show --query id -o tsv)"
for role in "Key Vault Secrets Officer" "App Configuration Data Owner"; do
  az role assignment create --assignee "$me" --role "$role" \
    --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/tx02v2-lab"
done
cd terraform/envs/lab
cp terraform.tfvars.example terraform.tfvars   # real private values; ignored file
export ARM_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
# Review the plan and run the same FINOPS.md pricing/budget/expiration checks before approval.
terraform apply tfplan
terraform output
```

## 5. Platform

Run platform action=install, profile=core(default)|full, target=primary(default)|secondary;
approve lab. Full requires LAB_NODE_VM_SIZE=Standard_D2as_v5 and LAB_NODE_COUNT=2 before apply.
The apply identity must be in LAB_CLUSTER_ADMIN_PRINCIPAL_IDS; ranges must admit runners.
platform/install.sh:

1. Reads App Configuration contract, ALB/ESO/OTel client IDs and Application Insights connection string;
   renders manifests before installation.
2. Creates temporary kubeconfig with az aks get-credentials and kubelogin azurecli conversion.
3. Downloads ALB Controller1.12.2, verifies platform/versions.env archive SHA256, installs in
   azure-alb-system and verifies pulled image digests.
4. Waits for azure-alb-external GatewayClass Accepted.
5. Installs ESO2.12.0 with Workload ID annotations.
6. Applies dx02v2/observability namespaces, Role/RoleBinding/ClusterSecretStore.
7. Installs OTel Collector in observability with tx02v2-lab-otel identity and
   tx02v2-lab-traces connection string ConfigMap; waits for azure-key-vault Ready.

Full installs cert-manager and an HTTP-only Gateway before enabling app/mTLS.
Wait for dx02v2-tls Ready; cert-manager manages its Secret, referenced by app HTTPS Gateway.
The specific HTTP-01 route remains on port80 during renewal; dx02v2 admits only AGC subnet→solver8089.
Public issuance/renewal remains unexecuted in Azure.

Secondary permits only tx02v2-lab-dr-agc/tx02v2-lab-dr-frontend in the lab group;
mixed regional pairs are refused. Standby prepares issuer/certificate without waiting on
primary-pointing DNS. Restore the current TLS Secret before pre-DNS smoke (CONTINUITY.md).

Full adds ambient Istio/waypoint, observability, ArgoCD GitOps, Gatekeeper, Kyverno,
Trivy Operator, Azure Blob Velero and Chaos Mesh (16 pinned charts).
The app-of-apps reads TX platform/gitops/main; ArgoCD follows DX public gitops/azure
and the selected azure/core/full/WAF overlay. Deploy configures real parameters/images/IDs/CIDRs
on the live Application; the public branch contains only example parameters.
ArgoCD stays ClusterIP; use port-forward.
Kyverno requires digest-pinned API/web images and promotion attestations from the fork's exact
deploy-azure.yml on main. Trivy/Kyverno use Workload ID reads restricted to two app repositories.
Uninstall deletes Applications first so reconciliation cannot recreate routes, then Kyverno policies
and monitoring PVCs including managed-csi disks.

Full explicitly reasserts the Collector client-ID annotation: a new helm upgrade -f does not
automatically retain core --set values. Image policy uses Kubernetes evaluation mode for Pod
extractors. During cloud acceptance prove signed-image admission, unsigned-image rejection and
Application Insights traces; HARNESS offline checks cannot substitute.

Velero writes Kubernetes objects to private Blob with velero/velero federated identity.
R9 also protects volume bytes with FSB/Kopia, not disk snapshots; PostgreSQL uses native backups.
Standby must retain the same escrow password; lifecycle never age-deletes live repository chunks.
After approval, inspect `velero backup create dx02v2-smoke --include-namespaces dx02v2 --wait`
and `velero backup describe dx02v2-smoke --details`.
Do not delete the real app namespace to test restore in production.
Azure backup/restore remains unexecuted.

### Isolated Velero restore exercise

Only during an approved full-profile run. This deletes a temporary ConfigMap namespace,
not dx02v2 or its database. Backup remains in Blob until removed; inspect each result.

```bash
NAMESPACE=velero-restore-drill
BACKUP="velero-restore-drill-$(date -u +%Y%m%d%H%M%S)"
RESTORE="${BACKUP}-restore"

kubectl create namespace "$NAMESPACE"
kubectl create configmap restore-proof --namespace "$NAMESPACE" --from-literal=payload=restored
velero backup create "$BACKUP" --include-namespaces "$NAMESPACE" --wait
velero backup describe "$BACKUP" --details
kubectl delete namespace "$NAMESPACE" --wait
velero restore create "$RESTORE" --from-backup "$BACKUP" --wait
velero restore describe "$RESTORE" --details
kubectl get configmap restore-proof --namespace "$NAMESPACE" -o jsonpath='{.data.payload}'
# Require "restored" and completed restore before cleanup.
kubectl delete namespace "$NAMESPACE" --wait
velero restore delete "$RESTORE" --confirm
velero backup delete "$BACKUP" --confirm
```

If backup/restore is not Completed, inspect backup/restore logs and BackupStorageLocation.
Correct identity/container/network/RBAC before retry. velero backup delete removes object-storage
bytes; kubectl delete backup alone leaves Blob data/charges. This ConfigMap exercise does not
prove PVC bytes; the separate local PVC drill and approved cloud recovery are documented in CONTINUITY.md.

For an installation predating contractv3, reapply bootstrap before lab apply:
Monitoring Metrics Publisher and Storage Blob Data Contributor joined the apply ABAC role list.

For laptop installation, your object ID must be cluster admin, your IP authorized, and your
identity have App Configuration read permission (such as Data Owner above):

```bash
make tools
az login && az account set --subscription <SUBSCRIPTION_ID>
APP_DEPLOYER_PRINCIPAL_IDS='[]' platform/install.sh   # same Terraform/GitHub list
az aks get-credentials --resource-group tx02v2-lab --name tx02v2-lab --file /tmp/tx02v2-lab.kubeconfig
kubelogin convert-kubeconfig -l azurecli --kubeconfig /tmp/tx02v2-lab.kubeconfig
export KUBECONFIG=/tmp/tx02v2-lab.kubeconfig
kubectl get gatewayclass azure-alb-external
kubectl get clustersecretstore azure-key-vault
kubectl -n dx02v2 get role,rolebinding
```

APP_DEPLOYER_PRINCIPAL_IDS must equal Terraform app_deployer_principal_ids:
Terraform grants Azure roles, platform grants RoleBinding.

## 6. Application release and deployment

Follow dx02v2 RUNBOOK.md:

1. On main, run publish-images with ci_run_id from a successful current-main push CI.
   It republishes the tested image IDs with SPDX SBOMs/provenance, without rebuilding.
2. Run deploy-azure from main with that publisher's release_run_id, target and matching
   platform_profile. deploy_mode=auto|gitops|push; auto chooses GitOps only when the Application
   exists, and refuses permission/connectivity errors.
3. It verifies release/signers before and after lab approval, reads the17 contract keys,
   promotes the same digests to ACR dx02v2/api and dx02v2/web (immutable commit tag), attests/verifies
   promotion, creates azure-pg-ca, publishes GitOps revision, waits for sync/ESO/rollouts and smoke.
   Full uses azure-full/azure-waf-full, HTTPS and waypoint. Core can use direct push.

A laptop deployer adds their object ID to LAB_APP_DEPLOYER_PRINCIPAL_IDS and reruns apply plus
platform for Azure roles and Kubernetes RoleBinding.

## 7. Smoke

```bash
terraform -chdir=terraform/envs/lab output -raw agc_frontend_fqdn
kubectl -n dx02v2 get gateway dx02v2                 # PROGRAMMED=True, frontend FQDN
curl -fsS "http://<FRONTEND_FQDN>/healthz"            # core web
curl -fsS "http://<FRONTEND_FQDN>/api/info"           # core API
kubectl -n dx02v2 get externalsecrets                # SecretSynced
kubectl -n dx02v2 get webapplicationfirewallpolicy    # WAF Accepted
```

Full smoke uses the delegated HTTPS hostname and checks HTTP→HTTPS301.
Expected, unverified: after requests, tx02v2-lab-traces shows dx02v2-api in Transaction search/app map.
If absent after minutes, inspect `kubectl -n observability logs deployment/opentelemetry-collector`.
azure_monitor401/403 suggests missing tx02v2-lab-otel role/federation.

Expected, unverified: Prevention WAF returns403 for SQL injection:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://<FRONTEND_FQDN>/api/info?id=1%27%20OR%20%271%27=%271"
```

Use the full HTTPS hostname when appropriate. Record results in cloud_run_report.

## 8. Destroy

Run terraform-destroy with confirm exactly `destroy tx02v2-lab` and lab approval.
scripts/destroy.sh --subscription <ID>:

1. Inventories primary/secondary lab clusters and uninstalls platform where present, removing
   HTTPRoutes/Gateways/ALB policies/LoadBalancer Services and releases.
   Fixed lab names/resource group and Project=tx02v2 ownership checks prevent retargeting through
   RESOURCE_GROUP/CLUSTER_NAME environment values; kubeconfig is temporary.
2. Continues if uninstall fails (unreachable/unauthorized API, controller down, timeout).
   Terraform owns AGC/frontend/association; Service public IPs live in AKS node groups removed
   with clusters. A warning explicitly records failed uninstall.
3. Runs terraform destroy.

Fresh login and leftovers --retry-for900 execute with if:always, even after failure.
Read/correct/retry errors; never interpret them as empty inventory.
destroy-flow exercises the sequence using stub az/terraform/kubectl/helm/kubelogin.

```bash
export TF_STATE_STORAGE_ACCOUNT=<STATE_ACCOUNT> ARM_SUBSCRIPTION_ID=<ID>   # plus identical lab TF_VAR_*
scripts/destroy.sh --subscription "$ARM_SUBSCRIPTION_ID"   # Owner may use TF_VAR_purge_key_vault_on_destroy=true
scripts/leftovers.sh --subscription "$ARM_SUBSCRIPTION_ID" --retry-for 900
```

Cancelled/timed-out apply/destroy may leave the state Blob lease. The next Terraform command
shows Error acquiring the state lock and ID. Only after confirming no active operation, supply
force_unlock_id to destroy, or locally
`scripts/destroy.sh --subscription <ID> --force-unlock <ID>`.
If interrupted creation never reached state, subsequent apply may show already exists/
ResourceAlreadyExists: import the owned resource (terraform import <address> <id>) or delete it
after ownership review, then retry.

Bootstrap retains the empty tx02v2-lab group; AKS removes tx02v2-lab-nodes and DR node group.
Key Vault soft delete holds its name for seven days. Purge needs subscription-scope permission
absent from CI. leftovers prints exact INFO purge commands for lab vaults/deleted configuration stores:

```bash
az keyvault purge --name tx02v2-lab-<suffix> --location <location> --subscription <ID>
az appconfig purge --name tx02v2-lab-<suffix> --location <location> --subscription <ID> --yes
```

## 9. Leftovers

Always specify --subscription <ID>; every Azure call names it, so active az account set never
silently selects a scan target. Only Project=tx02v2 tags or owned lab/node groups count as leftovers.
Other-work IPs/LBs/disks/PostgreSQL/AGC are INFO ("not the lab's"), never removal candidates.
CI apply sees only its read permissions; inaccessible resources such as node groups are
UNCHECKED with a warning and unchanged exit status. For complete coverage, run as subscription Owner:

```bash
az login
scripts/leftovers.sh --subscription <SUBSCRIPTION_ID> --retry-for 900
```

BILLABLE means still charging (exit1); ORPHANED is free but obstructs reuse; INFO includes
bootstrap, soft-delete names and other work; UNCHECKED means not inspected.
Exit2 means authentication/API failure. Manual cleanup applies **only to BILLABLE/ORPHANED**;
check Project=tx02v2 or tx02v2-lab ownership first:

```bash
az resource delete --ids <RESOURCE_ID>
az group delete --name tx02v2-lab-nodes --yes
az network public-ip delete --ids <RESOURCE_ID>
az network lb delete --ids <RESOURCE_ID>
az disk delete --ids <RESOURCE_ID> --yes
az keyvault purge --name tx02v2-lab-<suffix> --location <location>
az monitor log-analytics workspace delete --resource-group tx02v2-lab --workspace-name tx02v2-lab-logs --force --yes
```

Repeat inventory until no BILLABLE items remain.

## 10. Final bootstrap teardown

1. Lab destroyed; complete Owner-run leftovers clean.
2. Return migrated bootstrap state to local (section2).
3. Remove manually granted roles (section4, plus ALB Reader if used):
   `az role assignment delete --assignee <OBJECT_ID> --role "<role>" --scope <scope>`.
4. In terraform/bootstrap set state_protection_lock=false, terraform apply to remove the lock,
   then terraform destroy. This removes state account/all versions, three identities, role
   assignments, budget and both groups; tx02v2-lab must be empty. Provider registrations remain
   and cost nothing.
5. Purge remaining soft-deleted Key Vault or wait seven days.
6. Check Cost Management the next day.

## 11. Run record

Open Cloud run report: date, region, subscription offer, both repository commits, versions, steps,
duration, Cost Management observations grouped by meter (include whether AKS
FreeTierInfrastructureCost appeared; COSTS.md), issues and redacted leftovers output.
Only this evidence changes the README cloud status.

## 12. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| init403 AuthorizationPermissionMismatch | missing/propagating container data role | wait; verify bootstrap Storage Blob Data Contributor |
| MissingSubscriptionRegistration | bootstrap absent in selected subscription | bootstrap section2 |
| LocationIsOfferRestricted | Free Trial offer restriction | inspect pay-as-you-go/region options; match bootstrap/lab location |
| local apply403 writing secrets/keys | Owner lacks data roles | section4 |
| Key Vault name conflict on recreation | previous soft-deleted vault | Owner purge or wait7days |
| API server not reachable | IP outside authorized ranges or identity not cluster admin | correct input, reapply |
| AADSTS700024 assertion outside valid time | GitHub assertion expired before az obtained tokens | rerun workflow |
| App Configuration429 | Free tier1000requests/day | wait until UTC midnight |
| ALB unauthorized on node group | documented missing Reader deviation | ARCHITECTURE.md |
| leftovers exit2 | no login/API error | authenticate/retry; never treat as clean |
