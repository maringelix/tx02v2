#!/usr/bin/env bash
# Destroys the lab: the platform layer and terraform/envs/lab. CLOUD-MUTATING. Run by
# .github/workflows/terraform-destroy.yml (after the typed confirmation and the approval of the lab
# environment), which follows it with a fresh login and scripts/leftovers.sh (if: always()); by hand
# it needs the same environment as the workflow.
#   1. platform/uninstall.sh, when the cluster exists (it deletes the Routes, Gateways and
#      LoadBalancer Services). When it fails (API server unreachable from here, controller stopped,
#      timeout) the destroy goes on: in this lab the controller owns no Azure resource (the AGC, its
#      frontend and its subnet association belong to Terraform, and the public IPs of the Services
#      live in the node resource group, which AKS deletes with the cluster).
#   2. terraform init, then destroy, also after a failed step 1.
# Exit code 0 only when terraform destroy passed; a failed uninstall is a warning. Every failure is
# printed, nothing is ignored.
# usage: scripts/destroy.sh --subscription ID [--force-unlock LOCK_ID]
#   --subscription  the subscription of the lab; the Azure CLI must be logged in to it (the script
#                   refuses to run against another active subscription)
#   --force-unlock  first removes the Terraform state lock of an interrupted apply or destroy (the
#                   lease of the state blob); LOCK_ID is the "ID" of the lock error message.
# Environment: TF_STATE_STORAGE_ACCOUNT, ARM_* and the TF_VAR_* variables of the lab (as in the
# workflow).
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

TF_DIR="$REPO_ROOT/terraform/envs/lab"

usage() {
  echo "usage: $0 --subscription ID [--force-unlock LOCK_ID]" >&2
  exit 2
}

main() {
  local subscription="" force_unlock="" clusters rc=0
  while (($# > 0)); do
    case "$1" in
      --subscription)
        [[ "${2:-}" =~ $GUID_RE ]] || usage
        subscription=$2
        shift 2
        ;;
      --force-unlock)
        [[ "${2:-}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || usage
        force_unlock=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ -n "$subscription" ]] || usage
  require_cmd az terraform
  require_az_login
  [[ "$(subscription_id)" == "$subscription" ]] ||
    die "the active subscription of the Azure CLI is not the one you named: az account set --subscription <ID>, then run again"
  [[ -n "${TF_STATE_STORAGE_ACCOUNT:-}" ]] || die "set TF_STATE_STORAGE_ACCOUNT to the state storage account of the bootstrap"

  clusters="$(az aks list --subscription "$subscription" --resource-group "$LAB_NAME" \
    --query "[?name=='$LAB_NAME'] | length(@)" --output tsv)" || clusters=unknown
  if [[ "$clusters" == 0 ]]; then
    log "cluster $LAB_NAME not found: nothing to uninstall"
  elif ! bash "$REPO_ROOT/platform/uninstall.sh"; then
    log "warning: platform/uninstall.sh did not finish; terraform destroy removes the AGC, the cluster and its node resource group anyway"
  fi

  terraform -chdir="$TF_DIR" init -input=false -lockfile=readonly \
    -backend-config="storage_account_name=$TF_STATE_STORAGE_ACCOUNT" || rc=1
  if [[ -n "$force_unlock" ]]; then
    terraform -chdir="$TF_DIR" force-unlock -force "$force_unlock" || rc=1
  fi
  terraform -chdir="$TF_DIR" destroy -auto-approve -input=false -no-color || rc=1
  return "$rc"
}

main "$@"
