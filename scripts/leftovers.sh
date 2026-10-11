#!/usr/bin/env bash
# Lists what the lab may have left behind after a destroy. Read-only (az list/show calls).
#   BILLABLE   still costs money (or may: unknown types count as billable) -> exit 1
#   ORPHANED   free, but blocks or confuses the next round (shown, exit code unaffected)
#   INFO       expected (bootstrap resources) or a name that stays reserved (soft-deleted vaults)
#   UNCHECKED  this identity may not read that scope: the CI identities are scoped to tx02v2-lab,
#              so run the script locally as the subscription Owner for a complete scan
# Usage: scripts/leftovers.sh [--retry-for SECONDS]   (needs `az login` or azure/login)
#   --retry-for re-scans every 60 s until nothing billable remains or the time is up (deletions
#   still running right after a destroy). Exit 2 on usage or Azure API errors.
# A dedicated subscription is assumed (docs/RUNBOOK.md): every public IP, load balancer, managed
# disk, Application Gateway for Containers and PostgreSQL server in it counts.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"

LAB_RG="$LAB_NAME"
NODE_RG="$LAB_NAME-nodes"
# Resource types without a charge of their own (anything else is treated as billable).
FREE_TYPES=" microsoft.managedidentity/userassignedidentities microsoft.network/networksecuritygroups microsoft.network/virtualnetworks microsoft.network/routetables microsoft.network/networkwatchers "

BILLABLE=0
UNCHECKED=0
NOT_FOUND=0
WORK_DIR=""
declare -A SEEN=()

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

usage() {
  echo "usage: $0 [--retry-for SECONDS]" >&2
  exit 2
}

found() { # LEVEL WHAT ITEMS... (billable and orphaned items are reported once)
  local level=$1 what=$2 item key
  shift 2
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    key="${item,,}"
    if [[ "$level" == BILLABLE || "$level" == ORPHANED ]]; then
      [[ -z "${SEEN[$key]:-}" ]] || continue
      SEEN[$key]=1
    fi
    printf '%-9s %-38s %s\n' "$level" "$what" "$item"
    if [[ "$level" == BILLABLE ]]; then
      BILLABLE=$((BILLABLE + 1))
    fi
  done
  return 0
}

# az_items NAME WHAT CMD... -> NAME=(non-empty output lines of an Azure CLI call). An authorization
# failure marks WHAT as UNCHECKED; a missing resource group sets NOT_FOUND=1; any other error
# exits 2 (an API error is never read as "nothing left").
az_items() {
  local -n _items=$1
  local what=$2 out rc=0 err="$WORK_DIR/az.err"
  shift 2
  _items=()
  NOT_FOUND=0
  out="$("$@" 2>"$err")" || rc=$?
  if ((rc != 0)); then
    if grep -qE 'AuthorizationFailed|does not have authorization' "$err"; then
      printf '%-9s %-38s %s\n' UNCHECKED "$what" "this identity cannot read it (run the scan locally as the subscription Owner)"
      UNCHECKED=$((UNCHECKED + 1))
      return 0
    fi
    if grep -qE 'ResourceGroupNotFound' "$err"; then
      NOT_FOUND=1
      return 0
    fi
    sed 's/^/  az: /' "$err" >&2
    echo "error: $what: the Azure CLI call failed with exit code $rc" >&2
    exit 2
  fi
  out="$(sed -e '/^[[:space:]]*$/d' <<<"$out")"
  [[ -z "$out" ]] || mapfile -t _items <<<"$out"
}

# classify WHAT "TYPE|ID"... -> BILLABLE, or ORPHANED for the free resource types.
classify() {
  local what=$1 entry type
  shift
  for entry in "$@"; do
    type="${entry%%|*}"
    if [[ "$FREE_TYPES" == *" ${type,,} "* ]]; then
      found ORPHANED "$what ($type)" "${entry#*|}"
    else
      found BILLABLE "$what ($type)" "${entry#*|}"
    fi
  done
}

scan() {
  local -a items=() pending=()
  local entry rg type id stack

  az_items items "resource group $LAB_RG" \
    az resource list --resource-group "$LAB_RG" --query "[].join('|', [type, id])" --output tsv
  if ((NOT_FOUND)); then
    found INFO "resource group $LAB_RG" "not found (bootstrap torn down?)"
  else
    classify "in $LAB_RG" "${items[@]}"
  fi

  # AKS deletes its node resource group with the cluster; if it is still there, so is the bill.
  az_items items "resource group $NODE_RG" az group show --name "$NODE_RG" --query id --output tsv
  if ((${#items[@]} > 0)); then
    found BILLABLE "AKS node resource group" "${items[@]}"
    az_items items "resource group $NODE_RG" \
      az resource list --resource-group "$NODE_RG" --query "[].join('|', [type, id])" --output tsv
    classify "in $NODE_RG" "${items[@]}"
  fi

  az_items items "Application Gateway for Containers" \
    az resource list --resource-type Microsoft.ServiceNetworking/trafficControllers --query '[].id' --output tsv
  found BILLABLE "Application Gateway for Containers" "${items[@]}"

  az_items items "PostgreSQL flexible servers" az postgres flexible-server list --query '[].id' --output tsv
  found BILLABLE "PostgreSQL flexible server" "${items[@]}"

  az_items items "public IP addresses" az network public-ip list --query '[].id' --output tsv
  found BILLABLE "public IP address" "${items[@]}"

  az_items items "load balancers" az network lb list --query '[].id' --output tsv
  found BILLABLE "load balancer" "${items[@]}"

  # PersistentVolumes with reclaimPolicy Retain survive the cluster as managed disks.
  az_items items "managed disks" az disk list --query '[].id' --output tsv
  found BILLABLE "managed disk" "${items[@]}"

  az_items items "Log Analytics workspaces" \
    az monitor log-analytics workspace list --query "[?starts_with(name, '$LAB_NAME')].id" --output tsv
  found BILLABLE "Log Analytics workspace" "${items[@]}"

  # Anything else tagged Project=tx02v2 outside the two lab groups (bootstrap resources are kept).
  az_items items "resources tagged Project=$LAB_PROJECT" \
    az resource list --tag "Project=$LAB_PROJECT" --query "[].join('|', [resourceGroup, type, id, tags.Stack || ''])" --output tsv
  pending=()
  for entry in "${items[@]}"; do
    IFS='|' read -r rg type id stack <<<"$entry"
    if [[ "$stack" == bootstrap ]]; then
      found INFO "bootstrap resource (kept)" "$id"
    elif [[ "${rg,,}" != "${LAB_RG,,}" && "${rg,,}" != "${NODE_RG,,}" ]]; then
      pending+=("$type|$id")
    fi
  done
  classify "tagged Project=$LAB_PROJECT" "${pending[@]}"

  # Names that stay reserved after a destroy (they block the next round, nothing is billed).
  az_items items "soft-deleted Key Vaults" \
    az keyvault list-deleted --resource-type vault --query "[?starts_with(name, '$LAB_NAME')].name" --output tsv
  found INFO "soft-deleted Key Vault (az keyvault purge --name <name>)" "${items[@]}"
  az_items items "deleted App Configuration stores" \
    az appconfig list-deleted --query "[?starts_with(name, '$LAB_NAME')].name" --output tsv
  found INFO "deleted App Configuration store" "${items[@]}"
  az_items items "deleted Log Analytics workspaces" \
    az monitor log-analytics workspace list-deleted-workspaces --query "[?starts_with(name, '$LAB_NAME')].name" --output tsv
  found INFO "soft-deleted Log Analytics workspace" "${items[@]}"
}

main() {
  local retry_for=0 deadline
  while (($# > 0)); do
    case "$1" in
      --retry-for)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
        retry_for=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  # Exit 2 (not 1) for setup problems, so they are never mistaken for "billable leftovers found".
  command -v az >/dev/null 2>&1 || {
    echo "error: the Azure CLI (az) is required" >&2
    exit 2
  }
  az account show --query id --output tsv >/dev/null || {
    echo "error: the Azure CLI is not logged in (az login, or azure/login in the workflow)" >&2
    exit 2
  }
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  deadline=$((SECONDS + retry_for))
  while :; do
    BILLABLE=0
    UNCHECKED=0
    SEEN=()
    log "scanning the active subscription for leftovers of $LAB_NAME ..."
    scan
    if ((UNCHECKED > 0)); then
      log "warning: $UNCHECKED scan(s) were not possible with this identity: run scripts/leftovers.sh locally as the subscription Owner (docs/RUNBOOK.md)."
    fi
    if ((BILLABLE == 0)); then
      log "result: nothing billable left by $LAB_NAME in the scanned scopes."
      return 0
    fi
    if ((SECONDS + 60 > deadline)); then
      log "result: $BILLABLE billable leftover(s). Delete them (docs/RUNBOOK.md, section sobras) and re-run."
      return 1
    fi
    log "$BILLABLE billable item(s) still present; re-scanning in 60 s"
    sleep 60
  done
}

main "$@"
