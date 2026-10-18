# R10: scaling, capacity and FinOps

## Status and prerequisites

Built for forks; no operation has run in Azure (v2).
CI runs Docker. The cloud commands below require the fork owner's approved exercise, their
own domain/account and budget. FinOps is opt-in and requires the full profile.
The default local topology remains one node; the capacity drill uses three kind nodes and
recommends 12 GiB available to Docker. Do not combine HA with `LOCAL_SIZE=small`.

## Local lesson: HPA, PDB and disruption

On Linux or in the devcontainer, run:

    make tools
    LOCAL_TOPOLOGY=ha LOCAL_FINOPS=1 make e2e

`scripts/local/capacity-drill.sh` creates a dedicated namespace and refuses to adopt an existing
one. A digest-pinned Node fixture generates CPU load in a worker thread, keeping HTTP responsive.
The probe requires HPA 1 → 3 → 1 under bounded load, rejection of eviction of the last Pod by its
PDB, draining a worker owned by kind, and redistribution of all three Pods across the remaining
nodes. The drain selects only the fixture, preserving the platform's persistent Pods.

The client accesses the Service throughout draining, measuring errors <= 1% and p99 <= 1 s.
It does not port-forward to an individual Pod. Cleanup always uncordons the node and deletes the
created namespace. Failures show Pods/HPA/PDB/VPA/events without printing Secrets. The JSON
report contains measurements and acceptance criteria. Existing mesh, backup, PITR, observability,
policy and Chaos probes remain mandatory.

VPA must produce a recommendation while retaining `updateMode Off` and the original requests.
OpenCost must return positive measured cost for the fixture namespace through `/allocation`.
Local rates are a deterministic simulation explicitly identified in
`platform/finops/pricing/local.json`.

## AKS autoscaler and Spot

The system pool has autoscaling enabled and an on-demand minimum >= 1. The user Spot pool is
opt-in: `enable_spot_pool=true` (`LAB_ENABLE_SPOT_POOL`), 0–2 nodes, an explicit taint,
`eviction_policy Delete`, and a positive `spot_max_price` (`LAB_SPOT_MAX_PRICE`). This is an
operator-selected maximum bid, with no promise of availability or actual price.
The module applies the same rules to the DR cluster. Critical services remain on the regular
pool; managed capacity receives evidence only after cloud validation.

During an approved run, apply `platform/finops/manifests/spot-job.yaml` after enabling the pool.
Observe events, scaling and the selected node. If Spot is unavailable, cancel the Job and run
a differently named copy without its Spot selector/toleration, selecting `agentpool=system`.
Preserve its deadline and record cost/results. Do not leave an attempt pending indefinitely.
Draining kind proves PDB/rescheduling behavior, not recovery of an Azure pool.

## Rates and installation

OpenCost 2.5.33 / 1.121.3 and VPA 0.14.0 / 1.8.0 have SHA256-pinned archives and images in
`platform/finops/versions.env` and the values files. The API is ClusterIP; UI, MCP and cloud
billing ingestion remain disabled. The exporter uses configured prices and the existing
Prometheus; it receives no billing credentials.

For cloud runs, provide `FINOPS_PRICING_FILE`: JSON with `cloud=azure`, the selected `region`,
`currency=USD`, `mode=estimate`, an HTTPS `source`, `asOf` reviewed within the past 31 days,
`description`, and positive decimal strings for `cpuPerCoreHour`, `ramPerGiBHour` and
`storagePerGiBHour`. Check current provider prices; the local simulation is not a quotation.
Spot uses the on-demand rate as a conservative upper bound.

During the approved run, the installer accepts `--profile full --finops`. The `platform` workflow
has a `finops` input and obtains rates from `LAB_FINOPS_PRICING_JSON`. Secondary requires rates
for the secondary region. Incorrect or stale inputs fail.
The Grafana dashboard "Lab FinOps" shows namespace CPU/RAM and explains idle/shared costs.
Compare `/allocation?window=1h&aggregate=namespace&includeIdle=true` and
`aggregate=label:cost_lab_owner` for showback. Owner/environment labels are mandatory in the
lessons; DX repositories check their own manifests and exercise rightsizing under an SLO.

## Estimate before apply and expiration

The `terraform-plan` and `terraform-apply` workflows call `scripts/cost-workflow.sh` after saving
`tfplan`; apply proceeds only if the gate passes.
Configure `LAB_FINOPS_PRICING_JSON`, `LAB_COST_BUDGET_USD`, `LAB_COST_HOURS` (<= 24), and
`LAB_COST_EXPIRES_AT` (UTC within the next 24 hours). Refresh the deadline for each run.
The budgeted duration must cover the deadline. These public inputs contain no identifiers.

To prepare the review worksheet outside CI:

    umask 077
    terraform -chdir=terraform/envs/lab show -json tfplan > /tmp/plan-private.json
    bash scripts/cost-pricing-template.sh azure eastus2 /tmp/plan-private.json /tmp/rates.json

The worksheet is intentionally incomplete: fill every resource type with a per-resource hourly
cost at the LARGEST planned configuration (HA/DR, maximum nodes, database sizes).
Use zero only for unbilled or already included types, recording the justification.
The gate rejects any unpriced type. It also requires external categories `backup`,
`controlPlane`, `database`, `dr`, `egress`, `loadBalancer`, `nat`, `storage` and `waf`,
including justified zeros to prevent double counting. These cover controller-created costs outside
Terraform. OpenCost CPU/RAM/disk rates and the plan inventory are complementary; do not sum the
reports as if they were separate invoices.

Plan JSON can contain secrets and must never become a public artifact. The report shows only
types, counts, rates, source/date, total, budget and expiration. CI fixtures prove arithmetic and
rejection of expensive scenarios, stale rates and unpriced resources. They are not Azure prices.

The budget is an alert and this gate is an estimate; neither caps billing.
Expiration blocks new plans/applies after the deadline and requires teardown at the end of the
lesson. It does not create an account-destruction bot with credentials. Use the existing teardown,
check leftovers, and record backup/state retention that continues to incur charges.
Stop load at the deadline even when the exercise fails.

## Diagnosis and limits

No HPA: inspect metrics-server, requests and `ScalingActive`. No rescheduling: inspect cordon,
PDB, affinity, quotas and events. VPA Off never updates requests automatically.
No allocation: inspect ServiceMonitor, Prometheus targets, a window with samples, exporter read
permissions and prices. Without reviewed regional pricing, the gate fails.
Compare load/SLO before and after; reducing requests alone does not establish savings.

Read [OpenCost Helm](https://opencost.io/docs/installation/helm/),
[allocation API](https://opencost.io/docs/integrations/api-examples/),
[AKS autoscaler](https://learn.microsoft.com/azure/aks/cluster-autoscaler) and
[AKS Spot](https://learn.microsoft.com/azure/aks/spot-node-pool).

### External cost, idle and owner on the dashboard

The rates file also requires `externalHourly` with `backup`, `controlPlane`, `database`,
`dr`, `egress`, `loadBalancer`, `nat`, `storage` and `waf` (USD/h). A zero requires an
inclusion/no-charge justification; do not count the same cost in both the Terraform resource
and an external category. The installer creates recording rule `lab_external_hourly_estimate`;
the dashboard shows categories, owner/environment, shared infrastructure and estimated idle.
Kube-state-metrics exposes only the two additional showback labels. The local simulation has
zero external costs; the fork owner fills in cloud rates.

LimitRange supplies missing limits before quota (CPU 1, RAM 512Mi per container; default requests
10m/64Mi). Explicit requests/limits remain intact, including proxy resources. Quota stays enforced.

For a DR plan, estimate the largest SKU and highest rate across the covered regions; record this
choice in the source description. For the family's Autopilot comparison, node idle is a capacity
model rather than an idle-VM bill: allocation uses Pod requests.
