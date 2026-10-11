# shellcheck shell=bash
# Azure CLI helpers shared by platform/*.sh and scripts/leftovers.sh. Read-only calls only.
# Every function fails (non-zero) when the Azure call fails: callers must never treat an API error
# as "nothing found". Requires the Azure CLI (az login, or OIDC through azure/login in CI).

LAB_PROJECT="${LAB_PROJECT:-tx02v2}"
LAB_NAME="${LAB_NAME:-tx02v2-lab}"
LAB_KEY_PREFIX="${LAB_KEY_PREFIX:-tx02v2/lab/}"
GUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

declare -gA CONTRACT=()

# mask VALUE -> hides an identifier (object, client or tenant ID) in GitHub Actions logs, which are
# public for a public repository. Prints the workflow command on stdout: never call it inside $(...).
mask() {
  if [[ "${GITHUB_ACTIONS:-}" == true && -n "$1" ]]; then
    printf '::add-mask::%s\n' "$1"
  fi
}

# require_az_login -> fails unless the Azure CLI has an active account.
require_az_login() {
  az account show --query id --output tsv >/dev/null ||
    die "the Azure CLI is not logged in (az login, or azure/login in the workflow)."
}

# subscription_id / tenant_id of the active account.
subscription_id() { az account show --query id --output tsv; }
tenant_id() { az account show --query tenantId --output tsv; }

# lab_suffix SUBSCRIPTION_ID -> contract suffix: first 8 hex characters of sha1(subscription ID).
lab_suffix() {
  local h
  if command -v sha1sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha1sum)"
  else
    h="$(printf '%s' "$1" | shasum -a 1)"
  fi
  printf '%s' "${h:0:8}"
}

# appconfig_endpoint -> APPCONFIG_ENDPOINT, or the deterministic endpoint of the contract store.
appconfig_endpoint() {
  if [[ -n "${APPCONFIG_ENDPOINT:-}" ]]; then
    printf '%s' "$APPCONFIG_ENDPOINT"
    return 0
  fi
  local sub
  sub="$(subscription_id)" || return 1
  printf 'https://%s-%s.azconfig.io' "$LAB_NAME" "$(lab_suffix "$sub")"
}

# load_contract -> fills CONTRACT[<key without prefix>] from App Configuration (Entra ID auth).
load_contract() {
  local endpoint out key value
  endpoint="$(appconfig_endpoint)" || die "cannot determine the App Configuration endpoint"
  # Contract keys have no label ('\0' selects the null label, like the dx02v2 deploy).
  out="$(az appconfig kv list --endpoint "$endpoint" --auth-mode login --key "${LAB_KEY_PREFIX}*" \
    --label '\0' --all --query '[].[key, value]' --output tsv)" ||
    die "cannot read the contract keys from $endpoint (did terraform apply of terraform/envs/lab run? does this identity have App Configuration Data Reader?)"
  CONTRACT=()
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    CONTRACT["${key#"$LAB_KEY_PREFIX"}"]="$value"
  done <<<"$out"
  ((${#CONTRACT[@]} > 0)) || die "no contract key under ${LAB_KEY_PREFIX} in $endpoint"
}

# contract KEY -> value of tx02v2/lab/KEY (load_contract first).
contract() {
  [[ -n "${CONTRACT[$1]:-}" ]] || die "contract key ${LAB_KEY_PREFIX}$1 is missing or empty (docs/CONTRATO.md)"
  printf '%s' "${CONTRACT[$1]}"
}

# guids_from_json_list JSON -> the lowercase GUIDs of a JSON list such as ["<id>", "<id>"], one per line.
guids_from_json_list() {
  local item
  local -a items=()
  [[ "$1" =~ ^[[:space:]]*\[.*\][[:space:]]*$ ]] || die "expected a JSON list of object IDs, got: $1"
  mapfile -t items < <(grep -oE '"[^"]*"' <<<"$1" | tr -d '"')
  for item in "${items[@]}"; do
    [[ "$item" =~ $GUID_RE ]] || die "'$item' is not a lowercase object ID (GUID)"
    printf '%s\n' "$item"
  done
}

# words_to_lines -> one item per line from Azure CLI tsv output (drops empty lines).
words_to_lines() {
  tr '\t' '\n' | sed -e '/^[[:space:]]*$/d'
}
