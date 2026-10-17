#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
export MOCK_DIR=$WORK
mkdir -p "$WORK/bin"
cat >"$WORK/bin/az" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "account show "*) echo 00000000-0000-0000-0000-000000000000; exit ;;
esac
name='' vault='' file='' query=''
while (($#)); do
  case "$1" in
    --name) name=$2; shift 2 ;;
    --vault-name) vault=$2; shift 2 ;;
    --file) file=$2; shift 2 ;;
    --query) query=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$vault/$name" in
  tx02v2-lab-b602d594/tx02v2-lab-db-app)
    echo '{"username":"dx02v2","password":"CURRENT-FIXTURE","host":"primary.postgres.database.azure.com","port":"5432","dbname":"dx02v2"}' ;;
  tx02v2-lab-b602d594/tx02v2-lab-app-admin-token)
    printf '%048d\n' 1 ;;
  tx02v2-lab-b602d594-dr/)
    for item in tx02v2-lab-dr-db-app tx02v2-lab-dr-app-admin-token; do
      if [[ "$query" == *"$item"* && -f "$MOCK_DIR/$item" ]]; then echo "$item"; fi
    done ;;
  tx02v2-lab-b602d594-dr/tx02v2-lab-dr-*)
    if [[ -n "$file" ]]; then cp "$file" "$MOCK_DIR/$name"; echo write >>"$MOCK_DIR/writes"
    else cat "$MOCK_DIR/$name"; fi ;;
  *) echo 'unowned vault or secret' >&2; exit 1 ;;
esac
MOCK
chmod +x "$WORK/bin/az"
export PATH="$WORK/bin:$PATH"
host=tx02v2-lab-b602d594-dr-postgres.postgres.database.azure.com
bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host "$host"
jq -e --arg host "$host" '.password == "CURRENT-FIXTURE" and .host == $host' "$WORK/tx02v2-lab-dr-db-app" >/dev/null
[[ "$(wc -l <"$WORK/writes")" == 2 ]]
bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host "$host"
[[ "$(wc -l <"$WORK/writes")" == 2 ]]
if bash "$REPO_ROOT/scripts/sync-dr-secrets.sh" --db-host attacker.example.org >/dev/null 2>&1; then die 'arbitrary host accepted'; fi
echo 'PASS current credentials, owned vaults, host replacement, idempotency and invalid host refusal'
