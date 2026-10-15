#!/usr/bin/env bash
# Offline test of scripts/leftovers.sh with a simulated Azure CLI: no Azure account, nothing is read
# or created. Proves what docs/GUARDRAILS.md (SEC-10) promises about the leftover check: in a
# subscription that also holds other work, only the lab's resources are billable leftovers, the rest
# is INFO "(not the lab's)", every az call names the subscription, and a soft-deleted vault comes
# with the exact command that purges it.
# Run by the harness (check leftovers-flow); usage: scripts/tests/leftovers-flow.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
SUB="00000000-0000-0000-0000-000000000000"
BASE="/subscriptions/$SUB/resourceGroups"

# The scripts under test run from a copy of the tree (they put .tools/bin in front of PATH).
mkdir -p "$WORK/repo/scripts" "$WORK/bin" "$WORK/state"
cp "$REPO_ROOT/scripts/leftovers.sh" "$WORK/repo/scripts/"
cp -r "$REPO_ROOT/scripts/lib" "$WORK/repo/scripts/lib"

# The simulated az answers what each list command of the scan would print with its --query: one
# "id|resourceGroup|Project" line per resource (scoped), "type|id" lines for a group, and so on.
# FAKE_SCENARIO=mixed: the lab and other work share the subscription; others: only other work.
cat >"$WORK/bin/az" <<EOF
#!/usr/bin/env bash
echo "az \$*" >>"\$FAKE_STATE/calls.log"
args="\$*"
not_found() {
  echo "ERROR: (ResourceGroupNotFound) Resource group not found." >&2
  exit 3
}
case "\$1 \$2" in
  "account show") echo "$SUB" ;;
  "group show")
    [[ "\$FAKE_SCENARIO" == mixed && "\$args" == *"--name tx02v2-lab-nodes"* ]] || not_found
    echo "$BASE/tx02v2-lab-nodes"
    ;;
  "resource list")
    if [[ "\$args" == *"--resource-group tx02v2-lab-nodes"* ]]; then
      echo "Microsoft.Network/publicIPAddresses|$BASE/tx02v2-lab-nodes/providers/Microsoft.Network/publicIPAddresses/aks-ingress"
    elif [[ "\$args" == *"--resource-group tx02v2-lab"* ]]; then
      [[ "\$FAKE_SCENARIO" == mixed ]] || not_found
      echo "Microsoft.ContainerService/managedClusters|$BASE/tx02v2-lab/providers/Microsoft.ContainerService/managedClusters/tx02v2-lab"
      echo "Microsoft.ManagedIdentity/userAssignedIdentities|$BASE/tx02v2-lab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/tx02v2-lab-aks"
    elif [[ "\$args" == *"--resource-type Microsoft.ServiceNetworking/trafficControllers"* ]]; then
      [[ "\$FAKE_SCENARIO" == mixed ]] && echo "$BASE/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc|tx02v2-lab|tx02v2"
      echo "$BASE/other-work/providers/Microsoft.ServiceNetworking/trafficControllers/their-agc|other-work|"
    fi
    ;;
  "postgres flexible-server")
    echo "$BASE/other-work/providers/Microsoft.DBforPostgreSQL/flexibleServers/their-db|other-work|"
    ;;
  "network public-ip")
    echo "$BASE/other-work/providers/Microsoft.Network/publicIPAddresses/their-ip|other-work|"
    if [[ "\$FAKE_SCENARIO" == mixed ]]; then
      echo "$BASE/MC_TX02V2-LAB-NODES/providers/Microsoft.Network/publicIPAddresses/aks-ingress|TX02V2-LAB-NODES|"
      echo "$BASE/somewhere/providers/Microsoft.Network/publicIPAddresses/tagged-ip|somewhere|tx02v2"
    fi
    ;;
  "network lb")
    echo "$BASE/other-work/providers/Microsoft.Network/loadBalancers/their-lb|other-work|"
    ;;
  "disk list")
    echo "$BASE/other-work/providers/Microsoft.Compute/disks/their-disk|other-work|someone-else"
    ;;
  "keyvault list-deleted")
    [[ "\$FAKE_SCENARIO" == mixed ]] && echo "tx02v2-lab-ab12cd34|eastus2"
    ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/az"

run_case() { # NAME EXPECTED_EXIT SCENARIO ARGS...
  local name=$1 expected=$2 scenario=$3 rc=0
  shift 3
  rm -f "$WORK/state/calls.log"
  env PATH="$WORK/bin:$PATH" FAKE_STATE="$WORK/state" FAKE_SCENARIO="$scenario" \
    bash "$WORK/repo/scripts/leftovers.sh" "$@" >"$WORK/$name.out" 2>&1 || rc=$?
  if [[ -f "$WORK/state/calls.log" ]]; then cp "$WORK/state/calls.log" "$WORK/$name.calls"; else : >"$WORK/$name.calls"; fi
  if [[ "$rc" != "$expected" ]]; then
    echo "FAIL $name: exit code $rc, expected $expected"
    sed 's/^/    /' "$WORK/$name.out" | tail -n 25
    FAILED=1
  fi
}

has() { # NAME REGEX DESCRIPTION
  if grep -qE -- "$2" "$WORK/$1.out"; then echo "PASS $1: $3"; else echo "FAIL $1: $3"; FAILED=1; fi
}

lacks() { # NAME REGEX DESCRIPTION
  if grep -qE -- "$2" "$WORK/$1.out"; then echo "FAIL $1: $3"; FAILED=1; else echo "PASS $1: $3"; fi
}

main() {
  # 1. The lab and other work in the same subscription.
  run_case mixed 1 mixed --subscription "$SUB"
  has mixed '^BILLABLE +AKS node resource group' "the node resource group of the lab is billable"
  has mixed '^BILLABLE +in tx02v2-lab \(Microsoft.ContainerService/managedClusters\)' "the cluster of the lab is billable"
  has mixed '^ORPHANED +in tx02v2-lab \(Microsoft.ManagedIdentity/userAssignedIdentities\)' "a free resource type of the lab is only orphaned"
  has mixed '^BILLABLE +Application Gateway for Containers +.*tx02v2-lab-agc' "the AGC of the lab (resource group and tag) is billable"
  has mixed '^BILLABLE +public IP address +.*MC_TX02V2-LAB-NODES.*aks-ingress' "a public IP in the node group is billable, whatever the case of the group"
  has mixed '^BILLABLE +public IP address +.*tagged-ip' "a public IP tagged Project=tx02v2 is billable"
  lacks mixed '^BILLABLE.*(their-|other-work)' "nothing of other work is a billable leftover"
  has mixed "^INFO +public IP address \\(not the lab's\\) +.*their-ip" "the public IP of other work is INFO"
  has mixed "^INFO +load balancer \\(not the lab's\\) +.*their-lb" "the load balancer of other work is INFO"
  has mixed "^INFO +managed disk \\(not the lab's\\) +.*their-disk" "the disk of other work is INFO"
  has mixed "^INFO +PostgreSQL flexible server \\(not the lab's\\) +.*their-db" "the database of other work is INFO"
  has mixed "^INFO +Application Gateway for Containers \\(not the lab's\\) +.*their-agc" "the AGC of other work is INFO"
  has mixed "az keyvault purge --name tx02v2-lab-ab12cd34 --location eastus2 --subscription $SUB" "the exact purge command of the vault"
  if grep -E '^az ' "$WORK/mixed.calls" | grep -vq -- "--subscription $SUB"; then
    echo "FAIL mixed: an az call does not name the subscription:"
    grep -E '^az ' "$WORK/mixed.calls" | grep -v -- "--subscription $SUB" | head -n 3
    FAILED=1
  else
    echo "PASS mixed: every az call names the subscription"
  fi

  # 2. Only other work in the subscription: nothing of the lab is left, the check passes.
  run_case others 0 others --subscription "$SUB"
  lacks others '^BILLABLE' "no billable leftover when only other work is there"
  has others "not the lab's" "the resources of other work are still listed, as INFO"

  # 3. The subscription is always explicit.
  run_case usage 2 others
  has usage '^usage:' "no --subscription is a usage error"
  run_case bad-usage 2 others --subscription "not-a-guid"
  has bad-usage '^usage:' "a subscription that is not a GUID is a usage error"

  exit "$FAILED"
}

main "$@"
