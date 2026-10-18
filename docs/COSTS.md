# Lab costs

Hourly, daily and forgotten-month estimates for lab defaults in eastus2, to
review before creating resources. Base prices are **Azure Retail Prices API
references from 2026-10-11; full-profile additions use 2026-10-16**. Check the
official calculator before every run: USD pay-as-you-go list prices exclude
taxes, transfer and credits. Bootstrap budget uses the subscription billing
currency. These are not observed bills; v2 is not run in the cloud (v2).

## Component estimate (defaults, eastus2)

| Component | Default quantity | Reference price | USD/hour | USD/day | Forgotten month, 730 h |
|---|---|---|---|---|---|
| AKS Free control plane | 1 | No management charge per official page; see meter caveat below | 0.000 | 0.00 | 0.00 |
| Standard_D2als_v6 Linux nodes | 2, autoscaler 1–3 | 0.0804/node-hour | 0.161 | 3.86 | 117.38 |
| Node OS disk, Premium SSD P4 30 GB | 2 | 4.80/disk-month | 0.013 | 0.32 | 9.60 |
| AKS outbound Standard LB | 1, up to 5 rules | 0.025/h + 0.005/GB processed | 0.025 | 0.60 | 18.25 |
| AKS outbound Standard public IP | 1 | 0.005/h | 0.005 | 0.12 | 3.65 |
| AGC **with WAF**, default | 1 AGC/frontend/association, ~1 capacity unit | 0.031 + 0.018 + 0.216 + 0.014/h | 0.279 | 6.70 | 203.67 |
| AGC without WAF, enable_waf=false | Same | 0.017 + 0.010 + 0.120 + 0.008/h | (0.155) | (3.72) | (113.15) |
| PostgreSQL Flexible B_Standard_B1ms | 1 | 0.017/h | 0.017 | 0.41 | 12.41 |
| PostgreSQL storage | 32 GB | 0.115/GB-month | 0.005 | 0.12 | 3.68 |
| PostgreSQL backup, seven days/LRS | Up to 32 GB | Included to 100% of provisioned storage, then 0.095/GB-month | 0.000 | 0.00 | 0.00 |
| ACR Standard, repository ABAC | 1, 10 GB included | 0.6666/day | 0.0278 | 0.67 | 20.28 |
| PostgreSQL private DNS | 1 | 0.50/zone-month + 0.40/million queries | 0.001 | 0.02 | 0.50 |
| Key Vault Standard | 2 secrets | 0.03/10,000 operations | ~0 | ~0 | Cents |
| App Configuration Free | 1 | Free, 1,000 requests/day | 0.000 | 0.00 | 0.00 |
| Application Insights/workspace tx02v2-lab-traces, always (v2 contract) | A few MB/run, each capped at 0.5 GB/day | Log Analytics ingestion below; 5 GB/month allowance covers lab volume | ~0 (up to 0.058 at cap) | ~0 (up to 1.38) | ~0 |
| Optional Log Analytics, enable_control_plane_logs=false | Cap 0.5 GB/day | 2.76/GB after billing account's 5 GB/month free, 31-day included retention | (up to 0.058) | (up to 1.38) | (up to ~28, ~42 if allowance consumed) |
| Terraform state, bootstrap Hot LRS Blob | A few KB | 0.0184/GB-month + operations | ~0 | ~0 | Cents |
| Identities/VNet/NSG/budget | — | No charge | 0.000 | 0.00 | 0.00 |
| **Total with WAF** | | | **~0.534** | **~12.81** | **~389** |
| **Total without WAF** | | | **~0.410** | **~9.84** | **~299** |

Assumptions: one frontend, one association and about one AGC capacity unit
(lab traffic; actual use depends on connections, throughput and compute); two
nodes throughout (autoscaler can fall to one or rise to three); control-plane
logs disabled.

ACR Standard is required for repository ABAC. Compared with former Basic, the
reference rises USD0.50/day, USD0.0208/h or about USD15.21/730h. Tables use
[Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)
pay-as-you-go references.

- A three-hour apply/platform/deploy/smoke/destroy run is about USD1.60 with WAF,
  USD1.23 without. LB, AGC and PostgreSQL round partial hours up to full hours.
- Left running, WAF defaults cost about USD12.81/day: budget 25 billing-currency
  units reaches 50% in about a day and 100% in about two, assuming USD billing.
- AGC/WAF is the largest item (~54%); association alone USD0.216/h (~42%).
  WAF adds USD0.124/h; nodes contribute ~31%.

## AKS FreeTierInfrastructureCost meter

### R9 continuity: HA and second region

Core retains the base table. HA uses General Purpose D2ads_v5 PostgreSQL,
two vCores. Retail Prices API returned **USD0.178/server-hour in eastus2** on
2026-10-17. Primary plus standby cost **USD0.356/h**, plus two 32 GiB SSD copies
(~USD0.010/h at the base rate). HA database is **~USD0.366/h**, versus core
~USD0.022/h: **~USD0.344/h extra, USD1.03/three hours, USD251/730h**.

DR also reserves a second AKS/nodes/disks/egress, ACR Standard, AGC/WAF,
secrets/configuration, backup and zonal PostgreSQL replica. Applying base prices
as a centralus reference and replacing B1ms with D2ads_v5 gives approximately
**USD0.695/h** for the second environment. HA primary plus secondary is
**~USD1.57/h, ~USD4.72/three hours, ~USD1,148/730h**, before interregion
egress, geo backup, full volumes/observability, restores, operations and taxes.
Destination rates may differ: this is a budget hypothesis, not a bill.
Idle standbys, replicas and nodes still incur charges.

Longer retention increases consumed backup blocks; geo backup differs from LRS.
PITR/geo restore creates a new server, charged until removed. Check
[PostgreSQL pricing](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/)
and [Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
for subscription region/currency before apply. No Azure bill has been measured.

Checked on 2026-10-11:

- Retail API lists AKS skuName FreeTierInfrastructureCost and meterName
  FreeTierInfrastructureCost Uptime SLA, USD0.05/h (0.0625 in some regions),
  effective 2026-10-01 across 61 regions including eastus2.
- [Official AKS pricing](https://azure.microsoft.com/pricing/details/kubernetes-service/)
  and [tier documentation](https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers)
  still describe Free as no management charge, only resource charges, and do not
  explain this meter or a billing change.

We could not establish what it covers or whether it charges a Free cluster.
Only an actual cluster/Cost Management observation can confirm. If applicable,
add USD0.05/h, USD1.20/day, USD36.50/730h. The original 2026-10-11 snapshot
quoted totals ~0.563/h with WAF/~0.439 without; after the ACR Standard update,
the current base totals plus this meter are **~0.584/h/~0.460/h**. During the
first cloud run, group cost by meter after several hours, record it in
cloud_run_report and update this section.

## Node sizing

AKS documentation checked 2026-10-11 rejects B-series in system pools; sizes
below two vCPUs/four GB may be rejected
([quotas/SKU/region restrictions](https://learn.microsoft.com/azure/aks/quotas-skus-regions)).
"Use system node pools" instead states four vCPUs; this lab follows the
restrictions page minimum, not yet cloud-validated. Default Standard_D2als_v6
(two vCPUs/four GiB/x86-64) was the cheapest conforming eastus2 choice;
node_vm_size rejects B-series (rejects_a_b_series_system_pool).
Linux alternatives from the same historical query:

| Size | vCPUs / memory | USD/hour |
|---|---|---|
| Standard_D2als_v6, default | 2 / 4 GiB | 0.0804 |
| Standard_D2als_v7 | 2 / 4 GiB | 0.0804 |
| Standard_F2s_v2 | 2 / 4 GiB | 0.0846 |
| Standard_D2ls_v5 | 2 / 4 GiB | 0.0850 |
| Standard_D2as_v5 | 2 / 8 GiB | 0.0860 |

Dalsv6 requires NVMe/gen2 images and lacks temporary disk, hence
node_os_disk_type="Managed". Before running, check subscription/region
availability with `az vm list-skus --location eastus2 --size Standard_D2als_v6 --all --output table`
(Restrictions column), and family quota with
`az vm list-usage --location eastus2 --output table`. Lab needs four family
vCPUs, six during one-node surge upgrade or autoscaling to three.

## Full-profile additional cost

Full requires an operator-owned registered domain. Terraform creates a billed
public Azure DNS zone/CNAME; see [DNS pricing](https://azure.microsoft.com/en-us/pricing/details/dns/).
Domain registration/renewal is excluded. Let's Encrypt certificates require no
purchase, but HTTP-01 depends on public delegation and a running AGC. Check
offer rates before running; totals below exclude DNS/domain.

Reference values from 2026-10-16 use two Standard_D2as_v5 nodes
(two vCPUs/eight GiB, USD0.086/h each), instead of two D2als_v6 at USD0.0804.
Pool increment is USD0.0112/h in eastus2. Full also uses Standard ACR for ABAC.

| Scenario | USD/hour | USD/day | USD/month, 730 h |
|---|---:|---:|---:|
| Full with WAF, no data disks | ~0.545 | ~13.08 | ~397.88 |
| Full without WAF, no data disks | ~0.421 | ~10.10 | ~307.35 |
| Full managed-csi PVCs: 3 × E3 16 GiB, 2 × E1 4 GiB | ~0.0058 | ~0.14 | ~4.20 |
| **Full with WAF/PVCs** | **~0.551** | **~13.22** | **~402.08** |
| **Full without WAF, with PVCs** | **~0.427** | **~10.24** | **~311.55** |
| Three hours with WAF/PVCs | — | — | ~1.65/run |
| Three hours without WAF, with PVCs | — | — | ~1.28/run |

Compute adds USD0.0112/h to core with other assumptions unchanged. Five PVCs
request 36 GiB and provision about 56 GiB of Standard SSD LRS: Prometheus12,
Loki 10 and Tempo 10 use E3 (16 GiB); Alertmanager/Grafana 2 each use E1 (4 GiB).
USD4.20/month uses eastus2 base rates, excluding disk transactions, Blob
storage/operations, traffic, optional logs and the possible FreeTier meter.
[Managed Disks](https://azure.microsoft.com/pricing/details/managed-disks/)
are charged by hour and accommodating tier; managed-csi uses managed disks.
Uninstall removes monitoring PVCs and their disks. Set LAB_NODE_VM_SIZE=Standard_D2as_v5
and LAB_NODE_COUNT=2 before plan/apply and retain them through destroy.
Full runs Grafana/Prometheus in-cluster, not their managed Azure services.
These are estimates; no cloud run occurred.

### Rendered requests and reference capacity

helm-template-full renders 16 pinned chart archives and calls
`scripts/platform-sizing.sh 2`. On 2026-10-16 manifests summed to this row.
DaemonSets count one instance/node; Prometheus/Alertmanager use spec.resources.
The check compares this row so chart changes cannot silently invalidate sizing.

| Profile | Chart requests | Reference nodes | Nominal capacity before AKS/app reserves |
|---|---:|---|---|
| full | 1335 mCPU / 3808 MiB | 2 × Standard_D2as_v5, 2 vCPU/8 GiB each | 4000 mCPU / 16384 MiB; charts ~33% CPU/~22% memory |

Requests are not measured use or allocatable capacity. Charts additionally
request managed-csi storage: Prometheus12, Alertmanager2, Grafana 2, Loki 10,
Tempo 10 GiB; disks incur charges while present. AKS system Pods, app and Azure
Monitor Agent are excluded. D2as_v5 provides memory margin, but rendering proves
neither successful cluster creation nor adequate runtime margin. Status remains
not run in the cloud (v2).

### Managed-observability comparison (R4.2)

The original R4.2 snapshot estimated in-cluster full at USD1.57/three hours with
WAF (1.20 without), before subsequent ACR/PVC adjustments above. Managed
observability retains the infrastructure and adds the following; no node saving
was assumed because managed-agent requests/allocatable capacity were unmeasured.

| Managed eastus2 item | Reference checked 2026-10-16 | Three-hour cost |
|---|---|---|
| Grafana Standard X1, two Standard Units | USD0.034246/unit-hour + USD6/active-user-month | ~USD0.2055 instance + USD6/active-user-month |
| Managed Prometheus | USD0.16/10 million ingested samples; USD0.001/10 million queried samples | Depends on run volume |
| Log Analytics | USD2.76/GB after billing account's first free5 GB/month | Depends on billable volume |

The historical comparison therefore started at USD1.78/three hours plus active
users and metrics/log volume, versus USD1.57 in-cluster. User cost may be charged
once/month rather than prorated to run duration. No 30-day Grafana promotion is
included. Exact cost requires observed samples/ingestion; Microsoft recommends
measured volumes and official calculator. Neither option has run in Azure.

## v1 scenarios (Azure, December 2025–January 2026)

From historical notes (LESSONS_LEARNED.md section 17), for comparison only:

| v1 scenario | Historical note |
|---|---|
| AKS base: two Standard_D2s_v3, Basic LB, state | ~USD272/month |
| Application Gateway WAF_v2, two instances | ~USD246/month base, USD250–350 average |
| Application Gateway Standard_v2 without WAF | ~USD125/month |
| Free Trial credit | ~USD200/30 days, estimated 25 AKS days |

The lesson remains: WAF ingress can cost as much as the rest combined. v2 replaces
Gateway v2 with hourly AGC, no instances, and permits disabling WAF.

## Tips

- Destroy the same day; run leftovers.sh locally as subscription Owner until no
  BILLABLE resource remains (RUNBOOK.md).
- enable_waf=false saves historical USD0.124/h but removes app WAF. DX uses the
  overlay without WebApplicationFirewallPolicy when waf/policy-id=none.
- Recalculate before changing node_count/size; autoscaler can reach three alone.
- Application Insights traces exist every run, usually a few MB; daily cap
  log_daily_quota_gb=0.5 bounds ingestion. Health probes create no spans.
- Optional control-plane logs use another 0.5 GB/day workspace; the free
  5 GB/month belongs to the billing account, not this lab.
- Trial credits hide the bill: check Cost Management in the first hours and keep
  budget alerts enabled.
- Deleted Key Vault names remain reserved for seven days, without charge;
  purge requires subscription permission (ARCHITECTURE.md).

## R10: capacity and FinOps

See [FinOps and scaling](FINOPS.md) for HA kind, load/HPA/PDB, OpenCost, VPA Off,
opt-in Spot, regional rates, budget/expiration and cleanup. Built for forks;
nothing in v2 has run in cloud.
