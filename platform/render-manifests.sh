#!/usr/bin/env bash
# Prints every platform/manifests/*.yaml as one multi-document YAML stream with the placeholders
# replaced. Used by platform/install.sh (| kubectl apply -f -) and by the harness
# (| kubeconform, contract-platform), so what is validated is exactly what gets applied. Needs no
# cluster.
# Usage: platform/render-manifests.sh <keyvault-uri> <deployer-object-id>[,<object-id>...] [--full <github-owner> --acr-login-server <host> --agc-subnet-cidr <cidr>] [--only <file>]
#   keyvault-uri        contract key keyvault/uri, e.g. https://tx02v2-lab-0a1b2c3d.vault.azure.net/
#   deployer object IDs contract key deploy/principal-id first, then app_deployer_principal_ids
# Placeholders are replaced only in their one allowed position (a value would otherwise leak
# into comments or break the YAML):
#   a line that is exactly __DEPLOYER_SUBJECTS__   -> one `kind: User` subject per object ID
#   `vaultUrl: __KEYVAULT_URI__`                     -> the Key Vault URI
# --full also renders fork repositories, ACR policy and the AGC edge CIDR from the fork/contract.
# Any other __NAME__ token left in the output is an error.
set -euo pipefail

GUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
VAULT_RE='^https://[a-z0-9-]{3,24}\.vault\.azure\.net/?$'
OWNER_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$'
ACR_RE='^[a-z0-9]{5,50}\.azurecr\.io$'
AGC_CIDR_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}/24$'
DX_REVISION=gitops/azure

usage() {
  echo "usage: $0 <keyvault-uri> <deployer-object-id>[,<object-id>...] [--full <github-owner> --acr-login-server <host> --agc-subnet-cidr <cidr>] [--only <file>]" >&2
  exit 2
}

main() {
  (($# >= 2)) || usage
  local vault_uri=$1 ids=$2 dir f id line n name subjects="" out="" owner="" acr="" agc_cidr="" only="" full=0 tx_repo_url="" dx_repo_url=""
  shift 2
  [[ "$vault_uri" =~ $VAULT_RE ]] || {
    echo "error: '$vault_uri' is not a Key Vault URI (https://<name>.vault.azure.net/)" >&2
    exit 2
  }
  local -a deployers=()
  IFS=',' read -ra deployers <<<"$ids"
  ((${#deployers[@]} > 0)) || usage
  for id in "${deployers[@]}"; do
    [[ "$id" =~ $GUID_RE ]] || {
      echo "error: '$id' is not a lowercase object ID (GUID)" >&2
      exit 2
    }
    [[ "$subjects" == *"name: $id"$'\n'* ]] && continue
    subjects+="  - kind: User"$'\n'"    name: $id"$'\n'"    apiGroup: rbac.authorization.k8s.io"$'\n'
  done

  while (($# > 0)); do
    case "$1" in
      --full)
        [[ "${2:-}" =~ $OWNER_RE ]] || usage
        owner=$2
        full=1
        shift 2
        ;;
      --acr-login-server)
        [[ "${2:-}" =~ $ACR_RE ]] || usage
        acr=$2
        shift 2
        ;;
      --agc-subnet-cidr)
        [[ "${2:-}" =~ $AGC_CIDR_RE ]] || usage
        agc_cidr=$2
        shift 2
        ;;
      --only)
        [[ "${2:-}" =~ ^[a-z0-9-]+(/[a-z0-9-]+)*\.yaml$ ]] || usage
        only=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  if ((full == 1)); then
    [[ -n "$acr" && -n "$agc_cidr" ]] || usage
    local -a octets=()
    IFS=. read -ra octets <<<"${agc_cidr%/24}"
    for id in "${octets[@]}"; do
      ((10#$id <= 255)) || usage
    done
    tx_repo_url="https://github.com/$owner/tx02v2.git"
    dx_repo_url="https://github.com/$owner/dx02v2.git"
  else
    [[ -z "$acr" && -z "$agc_cidr" && -z "$only" ]] || usage
  fi

  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifests"
  shopt -s nullglob
  local -a files=("$dir"/*.yaml)
  ((full == 0)) || files+=("$dir"/full/*.yaml)
  if [[ -n "$only" ]]; then
    [[ -f "$dir/$only" ]] || usage
    files=("$dir/$only")
  fi
  ((${#files[@]} > 0)) || {
    echo "error: no manifests in $dir" >&2
    exit 1
  }
  for f in "${files[@]}"; do
    name="platform/manifests/${f#"$dir"/}"
    out+="---"$'\n'"# Source: $name"$'\n'
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      if [[ "$line" == "__DEPLOYER_SUBJECTS__" ]]; then
        out+="$subjects"
        continue
      fi
      if ((full == 1)); then
        line="${line//__GITHUB_OWNER__/$owner}"
        line="${line//__TX_REPO_URL__/$tx_repo_url}"
        line="${line//__DX_REPO_URL__/$dx_repo_url}"
        line="${line//__DX_REVISION__/$DX_REVISION}"
        line="${line//__ACR_LOGIN_SERVER__/$acr}"
        line="${line//__AGC_SUBNET_CIDR__/$agc_cidr}"
      fi
      if [[ "$line" =~ ^([[:space:]]*vaultUrl:[[:space:]]+)__KEYVAULT_URI__$ ]]; then
        line="${BASH_REMATCH[1]}$vault_uri"
      fi
      if [[ "$line" =~ __[A-Z][A-Z0-9_]*__ ]]; then
        echo "error: $name:$n: placeholder ${BASH_REMATCH[0]} outside its allowed position" >&2
        exit 1
      fi
      out+="$line"$'\n'
    done <"$f"
  done
  printf '%s' "$out"
}

main "$@"
