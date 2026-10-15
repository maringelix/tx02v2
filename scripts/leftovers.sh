#!/usr/bin/env bash
# Lists what the lab may have left behind after a destroy. Read-only (az list/show calls).
#   BILLABLE   still costs money (or may: unknown types count as billable) -> exit 1
#   ORPHANED   free, but blocks or confuses the next round (shown, exit code unaffected)
#   INFO       expected (bootstrap resources) or a name that stays reserved (soft-deleted vaults)
#   UNCHECKED  this identity may not read that scope: the CI identities are scoped to tx02v2-lab,
#              so run the script locally as the subscription Owner for a complete scan
# Usage: scripts/leftovers.sh --subscription ID [--retry-for SECONDS]   (needs `az login` or azure/login)
#   --subscription  the subscription of the lab, always explicit: every az call names it, so the
#                   active account of the machine (`az account set`) never decides what is scanned
#   --retry-for     re-scans every 60 s until nothing billable remains or the time is up (deletions
#                   still running right after a destroy). Exit 2 on usage or Azure API errors.
# Only what belongs to the lab counts: a resource tagged Project=tx02v2, or in the resource groups
# tx02v2-lab and tx02v2-lab-nodes. The same kinds of resource of any other work in the subscription
# are listed as INFO "(not the lab's)", never as something to delete. The soft-deleted vaults and
# stores of the lab are listed with the exact command that purges them.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"

LAB_RG="$LAB_NAME"
NODE_RG="$LAB_NAME-nodes"
SUBSCRIPTION=""
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
  echo "usage: $0 --subscription ID [--retry-for SECONDS]" >&2
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
  out="$("$@" --subscription "$SUBSCRIPTION" 2>"$err")" || rc=$?
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

# lab_owned RESOURCE_GROUP PROJECT_TAG -> success when the resource is the lab's: tagged Project=tx02v2
# or in one of the two resource groups of the lab (resource group names compare case-insensitively:
# Azure reports the node group in upper case in some resource IDs).
lab_owned() {
  local rg="${1,,}"
  [[ "$2" == "$LAB_PROJECT" || "$rg" == "${LAB_RG,,}" || "$rg" == "${NODE_RG,,}" ]]
}

# scoped WHAT AZ_CMD... -> runs a list command of the subscription and reports every item: BILLABLE
# when it is the lab's, INFO "(not the lab's)" when it belongs to other work.
scoped() {
  local what=$1 line id rg project
  local -a items=()
  shift
  az_items items "$what" "$@" --query "[].join('|', [id, resourceGroup || '', tags.Project || ''])" --output tsv
  for line in "${items[@]}"; do
    IFS='|' read -r id rg project <<<"$line"
    if lab_owned "$rg" "$project"; then
      found BILLABLE "$what" "$id"
    else
      found INFO "$what (not the lab's)" "$id"
    fi
  done
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
  local entry rg type id stack line name location

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

  scoped "Application Gateway for Containers" \
    az resource list --resource-type Microsoft.ServiceNetworking/trafficControllers
  scoped "PostgreSQL flexible server" az postgres flexible-server list
  scoped "public IP address" az network public-ip list
  scoped "load balancer" az network lb list
  # PersistentVolumes with reclaimPolicy Retain survive the cluster as managed disks.
  scoped "managed disk" az disk list

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

  # Names that stay reserved after a destroy (they block the next round, nothing is billed). The
  # purge needs a permission at the scope of the subscription, which the CI identities do not have:
  # the exact command is printed to be run as the Owner (docs/RUNBOOK.md, section 8).
  az_items items "soft-deleted Key Vaults" \
    az keyvault list-deleted --resource-type vault \
    --query "[?starts_with(name, '$LAB_NAME')].join('|', [name, properties.location])" --output tsv
  for line in "${items[@]}"; do
    IFS='|' read -r name location <<<"$line"
    found INFO "soft-deleted Key Vault, free the name with" \
      "az keyvault purge --name $name --location $location --subscription $SUBSCRIPTION"
  done
  az_items items "deleted App Configuration stores" \
    az appconfig list-deleted --query "[?starts_with(name, '$LAB_NAME')].join('|', [name, location])" --output tsv
  for line in "${items[@]}"; do
    IFS='|' read -r name location <<<"$line"
    found INFO "deleted App Configuration store, free the name with" \
      "az appconfig purge --name $name --location $location --subscription $SUBSCRIPTION --yes"
  done
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
      --subscription)
        [[ "${2:-}" =~ $GUID_RE ]] || usage
        SUBSCRIPTION=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ -n "$SUBSCRIPTION" ]] || usage
  # Exit 2 (not 1) for setup problems, so they are never mistaken for "billable leftovers found".
  command -v az >/dev/null 2>&1 || {
    echo "error: the Azure CLI (az) is required" >&2
    exit 2
  }
  az account show --subscription "$SUBSCRIPTION" --query id --output tsv >/dev/null || {
    echo "error: the Azure CLI is not logged in, or this account cannot see the subscription (az login, or azure/login in the workflow)" >&2
    exit 2
  }
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  deadline=$((SECONDS + retry_for))
  while :; do
    BILLABLE=0
    UNCHECKED=0
    SEEN=()
    log "scanning the subscription $(printf '%s' "$SUBSCRIPTION" | cut -c1-8)... for leftovers of $LAB_NAME ..."
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
