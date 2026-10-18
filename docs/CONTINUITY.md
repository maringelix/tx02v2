# Data continuity: R9 (Azure)

## Additional Velero PVC proof

Local CI runs `scripts/local/volume-restore-drill.sh`: a restricted Pod writes bytes into a kind
`local` volume, requires `PodVolumeBackup Completed`, removes the namespace/PVC/PV and original
data, then restores. Passing requires a new PVC UID, `PodVolumeRestore Completed` and identical
SHA256. Restoring only a ConfigMap or an empty PVC does not satisfy this check.
The heavy execution runs in GitHub Actions.

FSB needs root/hostPath in the local Velero namespace; the server stays non-root and the
application keeps `restricted` Pod Security. The random Kopia repository password is created
before the first backup and preserved across reinstalls. Never publish that password or Secret
backups. Cloud uses its CSI driver and requires a separate approved exercise; kind results do
not certify managed snapshots.

HA/DR code uses Terraform tests with mocked providers. **No restore, promotion or failover has
run in Azure v2.** The Docker exercise uses real PostgreSQL but does not measure zone redundancy,
geographic lag or Azure subscription offer restrictions.

| `postgres_profile` | Primary | DR destination |
|---|---|---|
| `core` (default) | Burstable B1ms, 7 days of native backups/PITR, no standby | none |
| `ha` | General Purpose `GP_Standard_D2ads_v5`, ZoneRedundant standby, 7–35 days retention | none |
| `dr` | HA plus geo-redundant backups | private PostgreSQL replica, AKS, VNet, ACR, Key Vault, App Configuration, AGC/WAF and Velero in another region |

The HA/DR recipe validates the `eastus2`/`centralus` pair. Check SKU, zones, quotas and support
for your subscription offer before apply. Offline validation does not prove available capacity.
Core keeps its original cost; HA and DR are explicit choices with additional compute/storage costs.

`postgres_backup_retention_days` configures native PITR between 7 and 35 days. Geo-redundant
backup is selected **at creation**: changing `postgres_geo_backup` or entering `dr` from a server
without geo backup can recreate the database. Review the plan and migrate data first when data
must be preserved. Geo restore uses the latest available backup in the paired region, with
potential RPO up to one hour; it does not offer geographic PITR. The DR replica is asynchronous
too, so loss depends on lag.

`postgres_delete_lock=true` creates an Azure `CanNotDelete` lock only on the primary server.
This requires lock permission (Owner or a specific role); the CI Contributor gains no new powers.
Use an authorized identity and review removal before teardown. Terraform can remove its own lock
during destroy: the lock protects accidental deletion outside that flow, not a substitute for
plan review or backup. The default `false` permits teardown.

## Local and CI evidence

`terraform -chdir=terraform/envs/lab test` checks both-region composition, HA SKU, backups,
private networking, peering, cross-region DNS, resource/repository-scoped permissions and exact
Workload Identity subjects. It rejects an invalid profile, Burstable HA, repeated region and
overlapping subnets.

GitHub Actions runs `make e2e`. The `scripts/local/pitr-drill.sh` probe produces a physical
backup with a manifest, archives WAL to a separate volume, confirms a record before the restore
point, deletes it afterward, and recovers the chosen point in an isolated instance.
`pg_verifybackup` must reject a corrupted copy; the query must return the correct records within
the local 180-second limit. DX02v2 coordinates application reconnection, PVC/Velero and A/B
failover/failback proofs. A ConfigMap restore alone does not prove data recovery.

## Isolated restore and endpoint change

1. Record the PITR window, last full backup, app version/migrations, transaction marker,
   acceptable loss and temporary-instance cost. Freeze writes if corruption is active.
2. Perform PITR to a **new** Flexible Server in the same region using the
   [backup/restore documentation](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore).
   For regional loss, use the DR replica or geo restore in the paired region; these are different mechanisms.
3. Verify private access, TLS, counts, keys and markers. Record observed loss and seconds until a
   valid transaction. Validate migration compatibility before using the app version.
4. Update the database secret in Key Vault and wait for ESO; restart the API rollout, validate
   readiness, reads and idempotent writes. Only then release traffic. If the proof fails, keep
   the previous endpoint and preserve instances for comparison.

## Regional failover and failback

The operator needs explicit human approval for each cloud action. Declare the incident and prove
fencing of the primary writer: block deployments and incoming writes, and confirm that the old
server accepts no transactions. **If a single writer cannot be guaranteed, refuse promotion.**
Record lag, last replicated marker and acceptable loss before promoting. Private replication
uses peering of both VNets, bidirectional DNS, and only TCP/5432 between PostgreSQL subnets.

Follow [replica promotion](https://learn.microsoft.com/azure/postgresql/read-replica/concepts-read-replicas-geo)
for the installed CLI version. After promotion, review Terraform topology before any apply; do not
blindly reapply `create_mode=Replica` over a promoted server. The secondary has its own App
Configuration endpoint (output `dr_appconfig_endpoint`), registry, Key Vault and AGC.
Copy images by digest and secrets/configuration before the incident. Validate data, backup/PITR
on the new primary and an idempotent write before routing traffic to the secondary AGC.

For failback, recreate/resynchronize the original region from the current writer. Wait for
acceptable lag, freeze writes, fence the secondary and perform planned promotion. Revalidate
data and routing before reopening. Preserve hashes/evidence, record RPO/RTO and destroy temporary
resources after acceptance. Terraform state and backups need recoverable copies outside the
affected region; bootstrap's default state is versioned, but LRS is not a regional replica.

## Preparing standby, backups and state

1. Enable DR and set bootstrap `state_replication_type="RAGRS"`. Inspect conversion of an existing
   backend; never accept replacement of the bucket/container holding your state. State retains
   versions, soft delete and a lock.
2. Set environment secret `LAB_VELERO_REPOSITORY_PASSWORD` to 64 random hexadecimal characters
   and retain a private copy outside both regions. The same secret protects Kopia on both clusters.
   Do not rotate it after the first backup: existing repository data would become unreadable.
   Installation refuses a mismatch.
3. Protected apply synchronizes **current values** from the primary Key Vault, changing only the
   destination database FQDN. Repeat after rotation. Plan reads no values; apply already has
   Secrets Officer scoped to the lab resource group.
4. Install with `platform/install.sh --profile full --github-owner OWNER --target secondary`.
   Secondary AKS uses `gitops/azure-dr`, regional telemetry and its own backup. The
   `primary-recovery` destination reads the primary RAGRS storage account's secondary Blob
   endpoint, with **Storage Blob Data Reader only on that container**. Both subnets use
   Microsoft.Storage.Global; no public range was opened.
5. Check geo-replication completion/lag and Last Sync Time before accepting a backup.
   RAGRS is asynchronous and guarantees no zero RPO. Schedules have different names to avoid
   catalog collisions. Kopia garbage collection follows references: age-based lifecycle applies
   only to `backups/`, never to live repository chunks.
6. Standby cert-manager creates issuer/certificate without waiting for HTTP-01 while DNS still
   points to the primary. Before promoting traffic, restore only the labeled TLS Secret from
   an imported backup:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: standby-tls
  namespace: velero
spec:
  backupName: REPLACE_WITH_IMPORTED_BACKUP_NAME
  includedNamespaces: [dx02v2]
  includedResources: [secrets]
  labelSelector:
    matchLabels:
      lab.continuity/tls: "true"
```

Require Restore Completed, check validity/SAN and never publish TLS material. The certificate
must be in the backup before the incident. HTTP-01 renewal uses the new Gateway after DNS changes.
Smoke-test the DX on the standby address; only after fencing, promotion and data acceptance use
`active_region=secondary` / `LAB_ACTIVE_REGION` to move the CNAME. This input does not promote
the database.

Velero protects objects and PVC bytes through FSB/data mover; namespace `velero` permits
root/hostPath to read kubelet mounts, while application namespaces remain restricted.
Local restore checksums prove something different from native PostgreSQL backups.
`LabBackupTooOldOrMissing` (30 h) and `LabRestoreFailed` reach the configured Alertmanager/Slack.
Azure Monitor records the native lag alert (>60 s for 5 min); attach an action group during the
cloud exercise for notifications outside the portal.

During regional loss, read the chosen state version through the secondary endpoint into a
private directory, verify lineage/serial, and fence any previous apply. Never use two writable
backends simultaneously or publish state as an artifact. Destroy inventories both AKS clusters
before Terraform; review locks and retention before permitting deletion.
Managed recovery, ACME issuance and egress remain unvalidated in Azure v2.

## Operational references

- [HA and SKU/region restrictions](https://learn.microsoft.com/azure/postgresql/high-availability/concepts-high-availability)
- [Backup, PITR and geo restore](https://learn.microsoft.com/azure/postgresql/backup-restore/concepts-backup-restore)
- [Private networking and regional replication](https://learn.microsoft.com/azure/postgresql/network/concepts-networking-private)
- [Resource locks](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
