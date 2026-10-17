#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
select_lab_target primary
[[ "$LAB_NAME" == tx02v2-lab && "$LAB_RESOURCE_GROUP" == tx02v2-lab ]]
select_lab_target secondary
[[ "$LAB_NAME" == tx02v2-lab-dr && "$LAB_RESOURCE_GROUP" == tx02v2-lab && "$IDENTITY_PREFIX" == tx02v2-lab ]]
if (select_lab_target unrelated-cluster) >/dev/null 2>&1; then die 'arbitrary cluster accepted'; fi
for target in primary secondary; do
  out="$(bash "$REPO_ROOT/platform/render-manifests.sh" https://tx02v2-lab-0a1b2c3d.vault.azure.net/ \
    dddddddd-dddd-dddd-dddd-dddddddddddd --full example-owner --acr-login-server tx02v2lab0a1b2c3d.azurecr.io \
    --agc-subnet-cidr 10.20.4.0/24 --target "$target")"
  if [[ "$target" == secondary ]]; then [[ "$out" == *'dxRevision: gitops/azure-dr'* ]]
  else [[ "$out" == *'dxRevision: gitops/azure'* && "$out" != *'gitops/azure-dr'* ]]; fi
done
echo 'PASS fixed resource group, bounded regional targets and separate GitOps revisions'
