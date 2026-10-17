#!/usr/bin/env bash
# CLOUD-MUTATING: protected apply only; never publish current values in state, logs or artifacts.
set -euo pipefail
set +x
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
require_cmd az jq
[[ $# == 2 && "$1" == --db-host && "$2" =~ ^tx02v2-lab-[0-9a-f]{8}-dr-postgres\.postgres\.database\.azure\.com$ ]] ||
  die 'usage: sync-dr-secrets.sh --db-host <Terraform dr_postgres_fqdn>'
HOST=$2
SUB="$(subscription_id)"
[[ "$SUB" =~ $GUID_RE ]] || die 'invalid active Azure subscription'
VAULT="tx02v2-lab-$(lab_suffix "$SUB")"
umask 077
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
az keyvault secret show --vault-name "$VAULT" --name tx02v2-lab-db-app --query value -o tsv >"$WORK/db"
az keyvault secret show --vault-name "$VAULT" --name tx02v2-lab-app-admin-token --query value -o tsv >"$WORK/admin"
jq -e '(keys | sort) == ["dbname","host","password","port","username"] and all(.[]; type == "string" and length > 0) and .port == "5432"' "$WORK/db" >/dev/null ||
  die 'primary DB credential schema is invalid'
jq -cS --arg host "$HOST" '.host = $host' "$WORK/db" >"$WORK/db-dr"
[[ "$(cat "$WORK/admin")" =~ ^[A-Za-z0-9]{48}$ ]] || die 'primary administrator token is invalid'
sync_value() {
  local name=$1 file=$2 existing
  existing="$(az keyvault secret list --vault-name "$VAULT-dr" --query "[?name=='$name'].name" -o tsv)"
  if [[ -n "$existing" ]]; then
    az keyvault secret show --vault-name "$VAULT-dr" --name "$name" --query value -o tsv >"$WORK/current"
    if [[ "$(cat "$file")" == "$(cat "$WORK/current")" ]]; then return; fi
  fi
  az keyvault secret set --vault-name "$VAULT-dr" --name "$name" --file "$file" --encoding utf-8 --output none
}
sync_value tx02v2-lab-dr-db-app "$WORK/db-dr"
sync_value tx02v2-lab-dr-app-admin-token "$WORK/admin"
log 'Current primary credentials synchronized; only the database hostname differs.'
