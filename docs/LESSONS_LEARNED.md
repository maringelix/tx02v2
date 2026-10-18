# Lessons from the Azure v1 lab (December 2025 to January 2026)

> The decision table and lessons preserve the starting state of each delivery.
> Current HA/backup/PITR/DR scope is in [CONTINUITY.md](CONTINUITY.md); capacity,
> OpenCost/VPA/Spot and estimates are in [FINOPS.md](FINOPS.md). Earlier out-of-scope
> decisions do not override the later R7–R10 implementation.

This document records failures in Azure v1 (tx02 and dx02, in a Free Trial subscription), their
causes and workarounds. It is a reference for operating and evolving tx02v2/dx02v2 without repeating
those mistakes. Identifiers, unique names, hosts, IPs and secrets from the notes are placeholders.

These lessons shaped the public tx02v2 redesign: AKS integrated with Microsoft Entra ID and Pod
Workload ID; GitHub OIDC-federated managed identities instead of service-principal secrets;
private PostgreSQL Flexible Server; Key Vault and External Secrets; Application Gateway for
Containers with WAF through Gateway API, following ingress-nginx retirement in March 2026;
bootstrap provider registration; a budget from day one; destroy followed by leftover checks;
and CI that needs no cloud credentials.

Every lesson follows **Symptom → Cause → Fix → Recommendation**. Fix describes the v1 action;
when no fix was recorded, this is explicit. **Outdated (October 2026)** marks versions, services
or practices that changed after those notes; check official documentation before relying on them.
Cost figures are collected in section 17.

## 1. Free Trial restrictions and quotas

### 1.1 Free Trial is not the same as free services

- **Symptom:** PostgreSQL Flexible Server creation failed with `LocationIsOfferRestricted`
  ("Offer is restricted for subscriptions in this region") in westus2, eastus and centralus.
  January 2026 plans again described PostgreSQL `B_Standard_B1ms` as free tier without rechecking.
- **Cause:** Free Trial blocks services/regions not mentioned in the public free-services list;
  having credit does not establish service access.
- **Fix:** switch the database to Azure SQL Database (section 7).
- **Recommendation:** prove each service with a minimal deployment in the real subscription before
  settling the architecture; date the result. Upgrading to pay-as-you-go removes offer restrictions
  and retains remaining credit until 30 days after signup.

### 1.2 AKS node SKU and region

- **Symptom:** `InvalidTemplateDeployment` for policy violations with `Standard_D2s_v3` in
  westus2/eastus and `Standard_DC2s_v3` in westus2.
- **Cause:** VM-size restrictions by offer and region.
- **Fix:** `standard_dc2s_v3` nodes (2 vCPU, 8 GB, confidential-compute family) in eastus, the only
  accepted pair; the cluster started in about five minutes.
- **Recommendation:** before fixing `node_size`, run
  `az vm list-skus --location <REGION> --size <SKU> --all --output table` (Restrictions column)
  and `az vm list-usage --location <REGION> --output table`; version the validated region/SKU pair.

### 1.3 vCPU quota and public-IP limit

- **Symptom:** January plans requested three 2-vCPU nodes; troubleshooting suggested a support
  request for "+10 B-family vCPUs". Grafana's LoadBalancer failed with `PublicIPCountLimitReached`.
- **Cause:** low offer quotas; Free Trial subscriptions cannot request quota/limit increases.
- **Fix:** use `kubectl port-forward` for Grafana, with guidance to reuse the ingress IP and delete
  unused IPs.
- **Recommendation:** size within quota, including upgrade surge nodes; use one public ingress IP.
  If quota is insufficient, upgrade to pay-as-you-go rather than opening a support request.

## 2. Costs

### 2.1 Conflicting estimates and zero-cost claims

- **Symptom:** contemporary documents priced the same base at US$0 ("100% free tier"), US$35–65/month,
  and about US$272/month; AKS, PostgreSQL B1ms and ACR Basic appeared as US$0.
- **Cause:** copied figures without price lookup, confusing credit consumption with no charges.
- **Fix:** none recorded; estimates were never reconciled.
- **Recommendation:** estimate through Azure Retail Prices API or the official calculator, date
  every price, and check actual Cost Management consumption in the first hours after each apply.

### 2.2 Ingress dominated cost

- **Symptom:** Application Gateway WAF_v2 with two instances cost as much as, or more than, the rest
  of the lab combined (section 17).
- **Cause:** v2 SKU charges fixed hours plus capacity units, 24/7, even without traffic.
- **Fix:** `deploy_app_gateway` workflow parameter, instructions to destroy unused gateways,
  and Standard_v2 without WAF as an alternative.
- **Recommendation:** make ingress independently disposable; in v2 the largest item is hourly
  Application Gateway for Containers with WAF.

### 2.3 A budget only in the plan

- **Symptom:** the R$400 ceiling existed only in notes; "configure cost alerts" remained a next step.
  R$1,078.95 of credit (about US$200) was estimated to last roughly 25 days in AKS mode.
- **Cause:** budget omitted from bootstrap.
- **Fix:** none recorded.
- **Recommendation:** bootstrap creates a subscription budget with actual/forecast alerts
  (for example 50%, 80%, 100%). It uses billing currency and only notifies; it cannot block spending.

### 2.4 Counting telemetry allowance twice

- **Symptom:** logging subtracted 5 GB/month free from roughly 24 GB/month; APM subtracted another
  5 GB for Application Insights.
- **Cause:** workspace-based Application Insights ingestion is billed through Log Analytics;
  the 5-GB/month allowance is per billing account.
- **Fix:** none recorded.
- **Recommendation:** one ingestion budget, weekly queries of `Usage`, application sampling,
  and exclusion of noisy namespaces from collection.

## 3. Terraform, state and provider registration

### 3.1 Resource-provider registration

- **Symptom:** registration failed because two `az provider register --namespace ... --wait`
  commands were pasted on one line; namespace lists differed across guides.
- **Cause:** improvised registration inside apply, no canonical list, provider configured with
  `skip_provider_registration = true`.
- **Fix:** one command per line with `--wait` for Microsoft.Network, Compute, Storage,
  ContainerService, OperationalInsights and Sql; ContainerRegistry and DBforPostgreSQL came later.
- **Recommendation:** bootstrap registers a versioned list using an authorized identity;
  the apply pipeline checks `registrationState`.
- **Outdated (October 2026):** azurerm 4.0 replaced `skip_provider_registration` with
  `resource_provider_registrations`. The provider major was 5 (5.9.0, checked 2026-10-11).

### 3.2 Plan waiting for input

- **Symptom:** CI `terraform plan` produced no output for more than 30 minutes until timeout;
  its log showed a `var.tags` prompt.
- **Cause:** unset variables and interactive Terraform input on a runner without a terminal.
- **Fix:** pass all 24 variables with `-var`, including `-var="tags={}"`; set a 15-minute timeout.
- **Recommendation:** `-input=false` in every CI command to fail promptly, and one versioned
  `.tfvars` per environment instead of repeated `-var` lists in plan, apply and import.

### 3.3 Plan/apply divergence

- **Symptom:** plan used `use_aks=false` while apply used `use_aks=true`; `db_version` was `12.0`
  (SQL Server's version reused for PostgreSQL) in one and `17` in the other. Only apply received
  sensitive `TF_VAR_*`; only plan used `-parallelism=10`.
- **Cause:** each workflow had its own variable copy; `use_aks=false` remained from isolating
  December's timeout, when the database module became temporarily conditional.
- **Fix:** manually synchronize both workflows.
- **Recommendation:** one variable source; apply the saved plan (`plan -out=tfplan`, `apply tfplan`)
  generated by the preceding job and approved through a protected environment. Keep artifact
  retention short because plans contain sensitive values.

### 3.4 Orphaned state lock

- **Symptom:** `Error acquiring the state lock` / "state blob is already locked" after cancellation
  or timeout.
- **Cause:** interruption leaves the blob lease unreleased.
- **Fix:** manual `az storage blob lease break`; later a step broke the lease before every plan
  with `continue-on-error: true`.
- **Recommendation:** never break locks automatically, which defeats concurrency protection.
  Use per-state GitHub Actions `concurrency` and manual `terraform force-unlock <LOCK_ID>` only
  after confirming no operation remains active.

### 3.5 HCL errors local validation would catch

- **Symptom:** `Missing false expression in conditional` (heredoc inside a ternary),
  `Unsupported attribute` for `virtual_network_id` on `data.azurerm_subnet`,
  `vars map does not contain key "admin_username"` in `templatefile()`,
  `Duplicate required providers configuration`, `Duplicate backend configuration`,
  `An argument named "use_cli" is not expected here` in the backend, and `terraform fmt -check` exit 3.
- **Cause:** unvalidated code was pushed; `versions.tf` and `provider.tf` duplicated blocks.
- **Fix:** `join()` instead of heredocs, a VNet data source, the missing template key, removal of
  `versions.tf`, `use_cli` only in the provider, and `terraform fmt -recursive`.
- **Recommendation:** credential-free pre-commit/CI with `fmt -check`, `init -backend=false`,
  `validate` and tflint before any cloud job, plus a single `terraform {}` block.
- **Outdated (October 2026):** workflows pinned Terraform 1.6.0; v2 uses 1.16.5
  (checked 2026-10-11).

### 3.6 Importing resources created outside Terraform

- **Symptom:** `A resource with the ID ".../servers/<SQL_SERVER>" already exists` on apply,
  `Cannot import non-existent remote object` before creation, and guides alternating between
  `module.database.` and `module.database[0].`.
- **Cause:** a portal-created database and a module `count` that changes resource addresses.
- **Fix:** a `terraform import` step before apply, repeating every variable and ending with `|| true`.
- **Recommendation:** declarative `import {}` rather than `terraform import ... || true`, which
  hides failures; preferably create every resource through Terraform.

### 3.7 Fixed names and docs/code divergence

- **Symptom:** "Storage account name already taken"; SQL server name held for 5–10 minutes after
  deletion; guides naming `rg-<proj>-<env>`/`aks-<proj>-<env>` while code created
  `<proj>-<env>-rg`/`<proj>-<env>-aks`. There were two ACR names, VNet 10.0.0.0/16 versus 10.1.0.0/16,
  gateway subnet 10.0.4.0/24 versus 10.0.5.0/24, and mismatched state container/blob names.
- **Cause:** fixed globally unique names and copied documentation literals.
- **Fix:** instructions to manually change `STORAGE_ACCOUNT` in bootstrap workflow.
- **Recommendation:** generate a random suffix once and store it in state for globally unique
  names (`<STORAGE_ACCOUNT>`, `<ACR_NAME>`, database server); scripts/docs read `terraform output`
  rather than repeat literals.

## 4. Identities and GitHub Actions

### 4.1 Service-principal client secret

- **Symptom:** `AADSTS7000215: Invalid client secret provided`, first because GitHub received the
  Secret ID (a GUID) instead of Value, then again in January 2026 during provider registration when
  the secret expired/rotated. Deleting the SP produced `AADSTS700016: Application not found`.
- **Cause:** long-lived secrets copied across repositories (`AZURE_CREDENTIALS` JSON and
  `AZURE_CLIENT_SECRET`), without an owner or rotation calendar.
- **Fix:** `az ad sp credential reset` and manual secret updates in each repository.
- **Recommendation:** GitHub OIDC with federated managed identity, exact repository/environment
  subject, no cloud secret in GitHub. v2 reversed the notes' conclusion favoring service principals
  over managed identities for workflows.
- **Outdated (October 2026):** `az ad sp create-for-rbac --sdk-auth` is deprecated; workflows used
  `azure/login@v1`, while current was v3 (checked 2026-10-11). Azure AD is now Microsoft Entra ID.

### 4.2 azure/login session conflicts with the provider

- **Symptom:** `Authenticating using the Azure CLI is only supported as a User (not a Service Principal)`.
- **Cause:** `azure/login` left a service-principal CLI session that azurerm attempted to use.
- **Fix:** remove `azure/login`, set `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` and
  `ARM_SUBSCRIPTION_ID`, then `use_cli = false`, `use_msi = false` and `use_oidc = false` in the provider.
- **Recommendation:** one explicit authentication method per job. v2 uses `ARM_USE_OIDC=true`
  with the managed identity client ID and azurerm backend `use_oidc`/`use_azuread_auth` instead of keys.

### 4.3 Broad privilege and static keys

- **Symptom:** a subscription-wide Contributor SP labeled least privilege and shared by infra/app;
  `ARM_ACCESS_KEY` for state, ACR admin user, and a suggestion to add Contributor to fix Chaos Studio 403.
- **Cause:** shortcuts to unblock the pipeline.
- **Fix:** none recorded; Key Vault was deferred until after deployment.
- **Recommendation:** one identity per function (read-only plan, apply, image push with AcrPush),
  scoped to the smallest resource group; no shared state-storage keys, use Storage Blob Data
  Contributor. Contributor cannot create AcrPull/Storage Blob Data role assignments; that needs
  `Microsoft.Authorization/roleAssignments/write`, preferably conditional RBAC Administrator.

### 4.4 Secrets in inputs, notes and literals

- **Symptom:** Argo CD admin password and Slack webhook in `workflow_dispatch` inputs, PFX/example
  passwords written in notes and suggested as real values, and `kubectl create secret --from-literal`
  with database passwords.
- **Cause:** no vault or secret-handling convention.
- **Fix:** none recorded.
- **Recommendation:** workflow inputs are not masked and must carry no secrets; Key Vault is the
  canonical source, External Secrets feeds the cluster, and CI gitleaks includes documentation.

### 4.5 Claiming validation without touching the cloud

- **Symptom:** January reports called infrastructure 100% validated and approved for deployment
  based on file/module/workflow counts, without Azure CLI or a real subscription plan.
  A rule forbidding local Terraform/az resource creation coexisted with az-configured gateway
  and a portal-created database.
- **Cause:** structural validation mistaken for functional validation.
- **Fix:** none recorded.
- **Recommendation:** separate credential-free checks (fmt, validate, tflint, Checkov, tests)
  from cloud plan/apply in a protected environment; always record what was and was not verified.

## 5. AKS

### 5.1 No canonical node size

- **Symptom:** notes named `standard_dc2s_v3` (the working size), `Standard_D2s_v3`,
  `Standard_DS2_v2` and `Standard_B2s` (2 vCPU, 4 GB) for the same cluster. Prometheus, Grafana and
  operator requests were halved to fit B2s or similar.
- **Cause:** values copied between guides without checking the actual deployment.
- **Fix:** none recorded.
- **Recommendation:** one node-size variable validated against quota/SKU; sum all add-on requests
  (Istio sidecars, monitoring, Argo CD, Gatekeeper, Chaos Mesh) before choosing 4-GB nodes;
  separate system and application node pools.

### 5.2 Kubernetes pinned without an upgrade plan

- **Symptom:** cluster on 1.32; quick reference used `az aks upgrade --kubernetes-version 1.32.0`.
- **Cause:** choose a version once, then copy it between guides.
- **Fix:** none recorded.
- **Recommendation:** choose with `az aks get-versions --location <REGION>`, enable patch/image
  upgrade channels and define a maintenance window.
- **Outdated (October 2026):** 1.32 is outside AKS standard support; the latest GA minor was 1.36,
  GA since 2026-06-30 (checked 2026-10-11).

### 5.3 Generic Kubernetes recipes on managed components

- **Symptom:** HPA troubleshooting applied metrics-server `latest`; logging guides disabled and
  re-enabled monitoring with `az aks disable-addons`/`enable-addons` after agent CrashLoopBackOff.
- **Cause:** instructions written for self-managed clusters.
- **Fix:** none recorded.
- **Recommendation:** AKS manages metrics-server already. Diagnose with `kubectl top`,
  `kubectl get apiservice v1beta1.metrics.k8s.io`, events and logs before reinstalling components.

## 6. Networking, ingress and Application Gateway/WAF

### 6.1 Gateway backends tied to node IPs and NodePorts

- **Symptom:** an empty backend pool, or one using NGINX's public IP, could not reach ClusterIP.
  Manual fix: `az network application-gateway address-pool update --servers <NODE_IP_1> <NODE_IP_2>`
  and `http-settings update --port <NODEPORT_HTTP>`.
- **Cause:** an external Application Gateway without a controller sees only VNet addresses.
- **Fix:** node private IPs and ingress-nginx NodePorts, read with `kubectl get nodes -o wide`
  and `kubectl get svc -n ingress-nginx`.
- **Recommendation:** avoid coupling ingress to nodes/ports; VMSS scaling/upgrades change IPs,
  and recreating the Service changed NodePorts (32371/31565 in December, 31805/31953 in January).
  Use a synchronizing controller such as Application Gateway for Containers ALB Controller.

### 6.2 Health probe returned 404

- **Symptom:** Unhealthy backends; the default probe received 404.
- **Cause:** no Host header, while ingress routes by hostname.
- **Fix:** `az network application-gateway probe create --host <HOST> --path /` associated with
  `http-settings` made backends Healthy.
- **Recommendation:** a dedicated hostname-independent health endpoint and an IaC-defined probe.

### 6.3 Manually copying the gateway certificate

- **Symptom:** HTTPS required exporting `tls.crt`/`tls.key` from cert-manager Secret, generating
  PFX with `openssl pkcs12 -export`, uploading through `ssl-cert create`, and creating port 443,
  SNI listener, probe and priority-200 HTTPS rule.
- **Cause:** gateway TLS termination while issuance/renewal happens inside the cluster.
- **Fix:** manual steps and a planned cron to resynchronize every 90-day renewal.
- **Recommendation:** terminate TLS where the certificate is managed (Gateway API/cert-manager or
  a gateway reference to Key Vault), avoiding manual private-key copies.
- **Outdated (October 2026):** Let's Encrypt ended expiration emails on 2025-06-04 and announced
  64-day validity from February 2027 and 45 days in 2028, making manual copying untenable.
  cert-manager replaced `installCRDs=true` with `crds.enabled=true`.

### 6.4 Ingress outside IaC

- **Symptom:** a security workflow separate from Terraform created gateway, WAF policy, public IP
  and subnet; remaining steps used manual az. A checklist planned four new jobs with
  `|| echo "already exists"` to appear idempotent.
- **Cause:** ingress began outside Terraform.
- **Fix:** none recorded; automation remained planned.
- **Recommendation:** Azure ingress resources in Terraform, Kubernetes Gateway/HTTPRoute/WAF objects
  in GitOps, so plan shows drift and destroy reaches everything.

### 6.5 WAF Detection without a Prevention deadline

- **Symptom:** WAF_v2 in Detection; `curl "http://<HOST>/?id=1' OR '1'='1"` only logged.
  Let's Encrypt staging certificates were untrusted by browsers.
- **Cause:** an initial false-positive avoidance setting without exit criteria.
- **Fix:** collect `ApplicationGatewayFirewallLog` through diagnostic settings and remain in
  Detection for 1–2 weeks.
- **Recommendation:** set a Prevention date/criterion, version justified exclusions, and require
  403 for the same payload afterward. Application Gateway for Containers WAF supported only
  DRS 2.1 (checked 2026-10-11).

### 6.6 Too many public IPs and dynamic DNS

- **Symptom:** dx02 LoadBalancer Service; separate IPs for ingress-nginx, Argo CD and Istio gateway;
  attempted Grafana LoadBalancer; dynamic DNS (`<HOST>`) manually updated after every new IP.
- **Cause:** expose each component separately.
- **Fix:** `kubectl port-forward` for operational tools.
- **Recommendation:** one public entry point; internal tools without public IPs; IaC-managed DNS
  deleted by destroy.
- **Outdated (October 2026):** ingress-nginx (v1 chart 4.11.3) retired in March 2026; the
  NGINX application-routing add-on support ends November 2026 (checked 2026-10-11).
  `ingressClassName` had replaced `kubernetes.io/ingress.class`; Basic Load Balancer/public IP
  retired on 2025-09-30.
+
+
+## 7. Database
+
+### 7.1 Azure SQL in another region through the portal
+
+- **Symptom:** `ProvisioningDisabled` ("Provisioning is restricted in this region") in eastus;
+  the free offer worked only in westus2, creating server/database in the portal with "Apply offer".
+- **Cause:** offer restrictions and a portal operation that Terraform did not reproduce.
+- **Fix:** manually create/import server and database; AKS in eastus reached westus2 through a
+  Private Endpoint and VNet-linked `privatelink.database.windows.net` zone.
+- **Recommendation:** do not change engine/region for offer restrictions without recording latency,
+  cross-region traffic and DR implications. The free offer was General Purpose serverless
+  (100,000 vCore-seconds/month in the notes), but Terraform declared Basic 2 GB; inspect the first
+  post-import plan to avoid an unintended SKU change.
+
+### 7.2 Engine migration broke SQL
+
+- **Symptom:** the app showed `connected: false` and `Incorrect syntax near 'current_user'`.
+- **Cause:** PostgreSQL-to-SQL Server migration left a `CURRENT_USER` query alias reserved in T-SQL.
+- **Fix:** `SELECT SYSTEM_USER AS db_user`.
+- **Recommendation:** integration-test the same cloud engine/version with a local container and
+  parameterized queries. v2 returns to PostgreSQL Flexible Server; reverse migration needs equal care.
+
+### 7.3 Public access and duplicated passwords
+
+- **Symptom:** public access and "Allow Azure services" enabled; admin password in GitHub
+  (`AZURE_SQL_PASSWORD`, `TF_VAR_db_password`), state and a Kubernetes Secret.
+  `Failed to connect to <SQL_SERVER>.database.windows.net:1433` was investigated with in-Pod `nslookup`.
+- **Cause:** shortcuts to make cross-region connectivity work.
+- **Fix:** Private Endpoint with a VNet-linked private zone.
+- **Recommendation:** disable public access; "Allow Azure services" permits connections from any
+  Azure resource, including other customers. Use Entra/managed identity where the driver supports
+  it; otherwise generate and store the password in Key Vault.
+
+## 8. ACR
+
+### 8.1 Admin user and GitHub credentials
+
+- **Symptom:** ACR Basic admin enabled; `ACR_USERNAME`/`ACR_PASSWORD` read by
+  `terraform output -raw` and stored in the application repository's secrets.
+- **Cause:** shortest path to CI `docker login`.
+- **Fix:** none recorded.
+- **Recommendation:** `admin_enabled = false`, OIDC CI with registry-scoped AcrPush, and no registry
+  passwords in outputs or state.
+
+### 8.2 Mixed registries and ImagePullBackOff
+
+- **Symptom:** `ImagePullBackOff` / "pull access denied" because an old manifest targeted Docker Hub.
+  Earlier GHCR pulls depended on a PAT-backed `imagePullSecret`.
+- **Cause:** three registries and pull secrets across the lab's lifetime.
+- **Fix:** ACR images and AcrPull for the kubelet identity, without imagePullSecrets.
+- **Recommendation:** one registry; prove integration with
+  `az aks check-acr --resource-group <RG> --name <AKS> --acr <ACR_NAME>.azurecr.io`;
+  use immutable commit-SHA tags or digests instead of `latest`.
+
+## 9. Observability
+
+### 9.1 Unstable kube-prometheus-stack on a small cluster
+
+- **Symptom:** Grafana CrashLoopBackOff from a duplicate sidecar datasource; Prometheus Operator
+  stuck in ContainerCreating waiting for its admission-webhook Secret; delayed PVCs;
+  `helm upgrade --install --wait --timeout=15m` hanging.
+- **Cause:** probably incomplete hook Jobs and unready Pods on a memory-constrained cluster.
+  The notes' explanation, excessive `--wait` checks, was not established.
+- **Fix:** disable datasource sidecar, admission webhooks, operator TLS and persistence;
+  remove `--wait`, use five-minute timeout and lower requests.
+- **Recommendation:** keep `--wait` or `--atomic` and inspect hook events/logs instead of disabling
+  protections; choose persistence/retention deliberately, not by elimination.
+
+### 9.2 Alerts that could not fire
+
+- **Symptom:** six dx02 rules for >5% errors, >1-s latency and database connectivity while the app
+  exposed no `/metrics`; Alertmanager receiver `null`; `unsupported scheme "" for URL` from an
+  empty webhook; plans to put the webhook directly in committed values.
+- **Cause:** rules preceded instrumentation.
+- **Fix:** disable Slack until a webhook existed.
+- **Recommendation:** instrument first (prom-client or OpenTelemetry), validate delivery with a
+  synthetic alert, and read `api_url_file` from a Key Vault-synchronized Secret.
+- **Outdated (October 2026):** Alertmanager routes replaced `match` with `matchers`.
+
+### 9.3 Default Grafana credentials
+
+- **Symptom:** chart-default username/password; port-forward after LoadBalancer failed.
+- **Cause:** accepting default values without review.
+- **Fix:** none recorded.
+- **Recommendation:** Key Vault-generated password delivered by External Secrets, or Entra SSO;
+  no operational UI on a public IP.
+
+### 9.4 Logging/APM guides detached from the app
+
+- **Symptom:** `ContainerLog` queries and `omsagent` troubleshooting; APM guide used
+  `applicationinsights` SDK `setup().start()`, `REACT_APP_*` in Vite, and separate backend/frontend
+  images while the app was one Express-served image. The APM SDK was never integrated.
+- **Cause:** generic guides written without inspecting the code.
+- **Fix:** none recorded.
+- **Recommendation:** start with the actual app: backend OpenTelemetry with
+  `@azure/monitor-opentelemetry`, Vite build-time `import.meta.env.VITE_*`, and sampling chosen
+  alongside the ingestion budget.
+- **Outdated (October 2026):** Container Insights uses Azure Monitor Agent (`ama-logs` Pods);
+  recommended schema is `ContainerLogV2`. Application Insights Node.js 3.x uses OpenTelemetry;
+  React deprecated `ReactDOM.render` in React 18.
+
+## 10. Service mesh
+
+### 10.1 An injection label ignored by the add-on
+
+- **Symptom:** after `az aks mesh enable`, namespace label `istio-injection=enabled` and docs
+  claiming implemented Pod mTLS.
+- **Cause:** AKS Istio add-on needs revision label `istio.io/rev=asm-X-Y`; it ignores the generic
+  injection label.
+- **Fix:** none recorded, nor was a sidecar verification recorded.
+- **Recommendation:** read `az aks show --query 'serviceMeshProfile.istio.revisions'`, label,
+  `kubectl rollout restart` and confirm `istio-proxy` before claiming mTLS.
+  Plan canary revision upgrades.
+
+### 10.2 Upstream Istio examples applied to the add-on
+
+- **Symptom:** `svc/istio-ingressgateway` commands and Gateway selector `istio: ingressgateway`,
+  while the add-on publishes `aks-istio-ingressgateway-external` in `aks-istio-ingress`.
+  Only the roadmap STRICT example used that selector; the notes said Telemetry API was unsupported.
+- **Cause:** copied upstream examples.
+- **Fix:** none recorded.
+- **Recommendation:** treat the add-on as a separate product: check AKS names, labels and limitations;
+  use `istioctl analyze` against `aks-istio-system`.
+- **Outdated (October 2026):** separate Pilot/Citadel/Galley predates istiod (2020);
+  `consecutive5xxErrors` replaced `consecutiveErrors`; `istioctl authn tls-check` no longer exists.
+
+### 10.3 PERMISSIVE for ingress outside the mesh
+
+- **Symptom:** PERMISSIVE accepted NGINX/gateway traffic without sidecars; sample
+  `mtls-strict.yaml` actually applied PERMISSIVE.
+- **Cause:** ingress was outside the mesh.
+- **Fix:** none; STRICT remained on the roadmap.
+- **Recommendation:** assess mesh value on a small cluster, accounting for every sidecar's
+  CPU/memory. If retained, use mesh-gateway ingress and namespace STRICT, testing the transition.
+
+## 11. GitOps
+
+### 11.1 Two deployment paths
+
+- **Symptom:** a workflow used `kubectl apply`; `kubectl delete pods -n dx02 --all` pulled `latest`;
+  an Argo CD Application with `prune`/`selfHeal` also owned dx02 manifests.
+- **Cause:** GitOps added without removing imperative deployment.
+- **Fix:** none recorded.
+- **Recommendation:** one resource owner: CI publishes an image and updates Git tag/digest;
+  Argo CD synchronizes and rollback uses `git revert`.
+
+### 11.2 Exposed, unpinned Argo CD
+
+- **Symptom:** HTTP LoadBalancer `argocd-server` with public IP; input-supplied admin password;
+  GitHub webhook at `http://<PUBLIC_IP>/api/webhook`; v2.13.3 installation manifest and `latest` CLI.
+- **Cause:** focus on getting the UI working.
+- **Fix:** none recorded.
+- **Recommendation:** no public IP (port-forward, or Entra SSO behind TLS gateway); disable local
+  admin after SSO, pin versions, use HTTPS/secret webhook or polling.
+- **Outdated (October 2026):** Argo CD 2.x is unsupported; the current line was 3.x.
+
+## 12. Policies
+
+### 12.1 Gatekeeper without a path to deny
+
+- **Symptom:** three policies: labels/limits in `dryrun`, privileged containers in `deny`.
+  Audit found five Pods without limits; exclusions covered kube-system, gatekeeper-system and monitoring.
+- **Cause:** gradual rollout without an owner/deadline.
+- **Fix:** none recorded.
+- **Recommendation:** dated dryrun → warn → deny stages with reviewed explicit exclusions.
+  Chaos Mesh was absent from the exception list although its daemon is privileged; resolve before install.
+
+### 12.2 A nonfunctional NetworkPolicy example
+
+- **Symptom:** ingress selected namespace label `name: ingress-nginx`, absent by default;
+  egress targeted `app: sql-server` Pods while the database was external PaaS.
+- **Cause:** an untested generic example.
+- **Fix:** none recorded.
+- **Recommendation:** select namespaces with `kubernetes.io/metadata.name`; allow PaaS egress through
+  the private-endpoint subnet `ipBlock` and kube-dns DNS; test an ephemeral Pod before deny-all.
+
+## 13. Chaos engineering
+
+### 13.1 No hypothesis or measurement
+
+- **Symptom:** measurement queries (`http_requests_total`, `http_request_duration_seconds_bucket`)
+  needed unexposed app metrics. "all-experiments" combined Pod kill every two minutes, 200-ms
+  latency, 80% CPU and 256-MB memory stress in `prd` for ten minutes.
+- **Cause:** tool selected before hypothesis/SLI.
+- **Fix:** none recorded.
+- **Recommendation:** written hypothesis, measured SLI, one failure at a time, abort criterion,
+  and a nonproduction environment.
+
+### 13.2 Chaos Mesh prerequisites and zero-cost claims
+
+- **Symptom:** reinstall failed with `CRDs already exist`; dry-run installed Chaos Mesh even
+  without experiments; suggested subscription Contributor for Chaos Studio 403; cost called zero.
+- **Cause:** incomplete cleanup, privilege shortcuts and ignored resource use.
+- **Fix:** `helm uninstall`, delete chaos-mesh namespace and CRDs before reinstall.
+- **Recommendation:** AKS uses containerd; configure `chaosDaemon.runtime=containerd` and
+  `chaosDaemon.socketPath=/run/containerd/containerd.sock`. Each privileged node daemon consumes
+  CPU/memory and needs an explicit policy exception.
+
+## 14. Backup and recovery
+
+### 14.1 DR based on a false premise
+
+- **Symptom:** westus2 database called built-in geographic redundancy, relying on geo restore,
+  while creation instructions selected locally redundant backup storage.
+- **Cause:** offer-imposed region mistaken for a DR design.
+- **Fix:** none recorded.
+- **Recommendation:** geo restore requires geo-redundant backup storage. Design, test and measure
+  DR (observed RTO/RPO, not copied targets).
+
+### 14.2 Backing up nonexistent resources
+
+- **Symptom:** configurable 7–30-day PITR for Basic database; planned snapshots of nonpersistent
+  Prometheus/Grafana PVs; restore PV used in-tree `azureDisk`; instructions waited for a weekly first full.
+- **Cause:** generic document not checked against deployment.
+- **Fix:** none recorded.
+- **Recommendation:** inspect each actual resource. Basic supports at most seven days PITR;
+  the first full is scheduled soon after database creation; restore disks with CSI
+  (`disk.csi.azure.com`) PVs.
+- **Outdated (October 2026):** Kubernetes 1.27 removed the in-tree `azureDisk` plugin.
+
+### 14.3 State restore used wrong names
+
+- **Symptom:** restore commands named different container/blob than the backend, listed snapshots
+  instead of versions, and promised 30-day soft delete while bootstrap configured seven days.
+- **Cause:** commands written without reading backend configuration.
+- **Fix:** none recorded.
+- **Recommendation:** derive commands from `backend`, configure bootstrap versioning/soft delete,
+  and rehearse state restore once per lab cycle.
+
+## 15. Security scanning
+
+### 15.1 Unpinned tools and actions
+
+- **Symptom:** `aquasecurity/trivy-action@master`,
+  `SonarSource/sonarcloud-github-action@master`, tfsec, `owasp/zap2docker-stable` and
+  scanner `-Dsonar.login`.
+- **Cause:** copied shortest-reference examples.
+- **Fix:** none recorded.
+- **Recommendation:** commit-SHA actions with Dependabot updates; image/IaC Trivy, Checkov and
+  gitleaks in credential-free CI.
+- **Outdated (October 2026):** tfsec merged into Trivy (`trivy config`); SonarCloud became
+  SonarQube Cloud; recommended action is `SonarSource/sonarqube-scan-action` with `sonar.token`
+  instead of `sonar.login`. ZAP image became `ghcr.io/zaproxy/zaproxy:stable`.
+
+### 15.2 Scans that blocked nothing
+
+- **Symptom:** trivy-action omitted `exit-code` (default 0), despite promised deployment blocking.
+  tx02 had security rating C and 0% reviewed SonarCloud hotspots. Static "Quality Gate Passed"
+  badges appeared while the gate was "Not computed". An IaC guide ignored TLS 1.0 as a free-tier limitation.
+- **Cause:** reporting tools mistaken for gates.
+- **Fix:** none recorded.
+- **Recommendation:** build, scan with `exit-code: 1`, then push; fail on HIGH/CRITICAL.
+  Dynamic badges, required quality-gate checks, technically justified time-bounded ignores.
+
+### 15.3 Fixes that introduce another problem
+
+- **Symptom:** blank page fixed by Helmet `contentSecurityPolicy: false`; NGINX
+  `configuration-snippet` headers including `X-XSS-Protection`; `git filter-branch` for a
+  historic secret; DAST targeted a public HTTP IP.
+- **Cause:** treating the immediate symptom.
+- **Fix:** CSP remained disabled.
+- **Recommendation:** on HTTP-only sites Helmet's default `upgrade-insecure-requests` commonly
+  causes blank pages: adjust that directive rather than disabling CSP. Rotate leaked credentials
+  first, then clean history with `git filter-repo`; target the TLS hostname for DAST.
+- **Outdated (October 2026):** `X-XSS-Protection` is obsolete in browsers; images used
+  `node:18-alpine` (EOL April 2025) and `node:20` (EOL April 2026).
+
+## 16. Cleanup and orphaned resources
+
+### 16.1 Destroy cannot reach resources Terraform did not create
+
+- **Symptom:** security workflow created gateway/WAF/public IP/subnet outside Terraform;
+  portal database entered state only if `|| true` import worked; Services created IPs/LBs in
+  `MC_<RG>_<AKS>_<REGION>`; Chaos Mesh CRDs remained. Guidance was destroy before each new apply
+  or `az group delete --name <RG> --yes --no-wait`.
+- **Cause:** multiple infrastructure owners.
+- **Fix:** destroy and manual resource-group deletion.
+- **Recommendation:** Terraform or GitOps creates everything; afterward check `az group list`
+  and `az resource list` filtered by lab tag, including IPs, disks, snapshots, private DNS zones,
+  workspaces and Azure's automatically created NetworkWatcherRG.
+
+### 16.2 Asynchronous deletion and retained names
+
+- **Symptom:** `--no-wait` returned before deletion finished; SQL server name remained reserved for
+  5–10 minutes; dynamic DNS retained the old IP until manually updated.
+- **Cause:** asynchronous operations and post-delete name retention.
+- **Fix:** wait and retry manually.
+- **Recommendation:** `az group wait --name <RG> --deleted` before leftover checks; account for
+  name-retaining soft delete (Key Vault, Log Analytics workspace) in recreation plans.
+  Destroy DNS records to avoid dangling references.
+
+## 17. Cost figures from the notes
+
+Historical reference estimates (December 2025 to January 2026), not a current budget.
+
+| Item | Figure in the notes |
+|---|---|
+| AKS, two Standard_D2s_v3 nodes | about US$150/month |
+| PostgreSQL Standard_D2s_v3, planned but never created | about US$100/month |
+| Basic Load Balancer | about US$20/month |
+| State storage | US$0.01–2/month depending on guide |
+| Base total in AKS mode | about US$272/month; VM mode about US$30/month |
+| January plan: three Standard_B2s nodes | US$30–50/month |
+| January plan: network and Private Endpoint | US$5–10/month and US$3–5/month |
+| January plan: declared total | US$38–65/month, pricing AKS control plane, PostgreSQL B1ms and ACR Basic at US$0 |
+| Two-instance Application Gateway WAF_v2 | base about US$246/month, US$0.008/GB processed, average US$250–350/month |
+| Gateway public IP | about US$4/month |
+| Application Gateway Standard_v2 without WAF | about US$125/month |
+| ingress-nginx LoadBalancer | US$20–30/month |
+| Log Analytics | 5 GB/month free; US$2.30/GB; extra retention US$0.10/GB/month |
+| Estimated logs, about 24 GB/month | about US$44/month, or US$20–40 with filters |
+| Application Insights, 50% sampling, about 2.2 GB/month | declared US$0; availability test US$1.20/test/month; multistep US$4.80/test/month |
+| Azure SQL Basic, backup included | about US$5/month |
+| SQL LTR, about 20 GB | about US$0.50/month (US$0.02/GB) |
+| Disk snapshots, 50 GB | about US$2.50/month (US$0.05/GB) |
+| Chaos Mesh | US$0 plus about US$5/month logs |
+| Free Trial credit | R$1,078.95 (about US$200) for 30 days, estimated 25 AKS-mode days |
+| Azure SQL free offer | 100,000 vCore-seconds/month |
+
+Still-relevant lessons: credit ran out in weeks; WAF ingress cost as much as or more than the
+remaining lab; ACR Basic is billed daily, not free; Basic Load Balancer/public IP retired on
+2025-09-30.
+
+The v2 largest item is Application Gateway for Containers with WAF: about US$0.28/hour
+(Azure Retail Prices API, eastus, 2026-10-11), assuming one frontend, one association and roughly
+one capacity unit, or about US$204/month if left running continuously.
