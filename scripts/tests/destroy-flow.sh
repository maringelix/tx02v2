#!/usr/bin/env bash
# Offline test of scripts/destroy.sh with simulated az, terraform, kubectl, helm and kubelogin: no
# Azure account, no cluster, nothing is created. Proves what docs/GUARDRAILS.md (CUSTO-03) promises:
# a destroy whose platform uninstall fails still runs terraform destroy, a failed terraform destroy
# fails the run, and a lock of an interrupted apply is released first.
# Run by the harness (check destroy-flow); usage: scripts/tests/destroy-flow.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
DESTROY_ARGS=()
SUB="00000000-0000-0000-0000-000000000000"

# The scripts under test run from a copy of the tree: they put .tools/bin (the real terraform,
# kubectl and helm of the harness) in front of PATH, which would shadow the simulated CLIs.
make_sandbox() {
  mkdir -p "$WORK/repo/scripts" "$WORK/repo/platform"
  cp "$REPO_ROOT/scripts/destroy.sh" "$WORK/repo/scripts/"
  cp -r "$REPO_ROOT/scripts/lib" "$WORK/repo/scripts/lib"
  cp "$REPO_ROOT/platform/uninstall.sh" "$WORK/repo/platform/"
}

make_fakes() {
  local bin="$WORK/bin"
  mkdir -p "$bin"
  cat >"$bin/az" <<EOF
#!/usr/bin/env bash
echo "az \$*" >>"\$FAKE_STATE/calls.log"
case "\$1 \$2" in
  "account show") echo "$SUB" ;;
  "aks list") echo "\${FAKE_CLUSTERS:-1}" ;;
  "aks show") echo tx02v2 ;;
  *) : ;;
esac
exit 0
EOF
  cat >"$bin/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$FAKE_STATE/calls.log"
if [[ "${FAKE_GITOPS:-0}" == 1 ]]; then
  case "$*" in
    *"get crd applications.argoproj.io"*) echo customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io ;;
    *"get crd httproutes.gateway.networking.k8s.io"*) echo customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io ;;
  esac
fi
if [[ "$*" == "get --raw /readyz" && "${FAKE_API_DOWN:-0}" == 1 ]]; then
  echo "the connection to the server was refused" >&2
  exit 1
fi
exit 0
EOF
  cat >"$bin/terraform" <<'EOF'
#!/usr/bin/env bash
echo "terraform $*" >>"$FAKE_STATE/calls.log"
if [[ " $* " == *" destroy "* && "${FAKE_TF_DESTROY_FAILS:-0}" == 1 ]]; then
  echo "Error: the destroy failed" >&2
  exit 1
fi
exit 0
EOF
  for tool in helm kubelogin; do
    cat >"$bin/$tool" <<'EOF'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$FAKE_STATE/calls.log"
exit 0
EOF
  done
  cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
n="$(cat "$FAKE_STATE/sleeps" 2>/dev/null || echo 0)"
echo $((n + 1)) >"$FAKE_STATE/sleeps"
((n < 60)) || { echo "the simulated sleep ran 60 times: a retry loop does not end" >&2; exit 1; }
EOF
  chmod +x "$bin"/*
}

# run_case NAME EXPECTED_EXIT [VAR=VALUE...] -> $WORK/<NAME>.out and $WORK/<NAME>.calls
run_case() {
  local name=$1 expected=$2 rc=0
  shift 2
  mkdir -p "$WORK/state"
  rm -f "$WORK/state"/*
  env "$@" PATH="$WORK/bin:$PATH" FAKE_STATE="$WORK/state" TF_STATE_STORAGE_ACCOUNT=tx02v2tfstate0123abcd \
    bash "$WORK/repo/scripts/destroy.sh" --subscription "$SUB" "${DESTROY_ARGS[@]}" >"$WORK/$name.out" 2>&1 || rc=$?
  cp "$WORK/state/calls.log" "$WORK/$name.calls"
  if [[ "$rc" != "$expected" ]]; then
    echo "FAIL $name: exit code $rc, expected $expected"
    sed 's/^/    /' "$WORK/$name.out" | tail -n 25
    FAILED=1
  fi
}

line_of() { # NAME REGEX -> first line number of the calls of the case that matches REGEX
  grep -nE -- "$2" "$WORK/$1.calls" | head -n 1 | cut -d: -f1
}

expect() { # NAME DESCRIPTION CONDITION(0 = true)
  if [[ "$3" == 0 ]]; then echo "PASS $1: $2"; else echo "FAIL $1: $2"; FAILED=1; fi
}

absent() { # NAME REGEX -> 0 when no call of the case matches
  if [[ -z "$(line_of "$1" "$2")" ]]; then echo 0; else echo 1; fi
}

present() { # NAME REGEX -> 0 when a call of the case matches
  if [[ -n "$(line_of "$1" "$2")" ]]; then echo 0; else echo 1; fi
}

output_has() { # NAME TEXT -> 0 when the output of the case contains TEXT
  if grep -qF -- "$2" "$WORK/$1.out"; then echo 0; else echo 1; fi
}

ordered() { # NAME REGEX_A REGEX_B -> 0 when A exists and comes before B
  local a b
  a="$(line_of "$1" "$2")"
  b="$(line_of "$1" "$3")"
  if [[ -n "$a" && -n "$b" ]] && ((a < b)); then echo 0; else echo 1; fi
}

main() {
  make_sandbox
  make_fakes

  # 1. The cluster API answers: the platform layer is uninstalled, then terraform destroy runs.
  run_case healthy 0
  expect healthy "the platform is uninstalled, then terraform destroy runs" \
    "$(ordered healthy 'helm uninstall' 'terraform .*destroy')"
  expect healthy "no warning about the uninstall" \
    "$(if grep -qF 'did not finish' "$WORK/healthy.out"; then echo 1; else echo 0; fi)"

  # 1b. With Argo CD installed, its parent and child Applications stop before Gateway routes are removed.
  run_case gitops 0 FAKE_GITOPS=1
  expect gitops "the Argo CD app-of-apps stops before the dx02v2 Application" \
    "$(ordered gitops 'kubectl delete applications.argoproj.io platform' 'kubectl delete applications.argoproj.io dx02v2')"
  expect gitops "GitOps stops before route cleanup so self-heal cannot recreate a Gateway" \
    "$(ordered gitops 'kubectl delete applications.argoproj.io platform' 'kubectl delete httproutes.gateway.networking.k8s.io')"

  # 2. The API server is unreachable: the uninstall fails, the destroy still runs and the run passes.
  run_case api-down 0 FAKE_API_DOWN=1
  expect api-down "the uninstall failure is reported as a warning" \
    "$(output_has api-down 'warning: platform/uninstall.sh did not finish')"
  expect api-down "terraform destroy still runs" \
    "$(present api-down 'terraform .*destroy')"

  # 3. No cluster: nothing to uninstall, terraform destroy runs.
  run_case no-cluster 0 FAKE_CLUSTERS=0
  expect no-cluster "the uninstall is skipped" "$(absent no-cluster 'kubectl ')"
  expect no-cluster "terraform destroy runs" \
    "$(present no-cluster 'terraform .*destroy')"

  # 4. terraform destroy fails: the run fails.
  run_case destroy-fails 1 FAKE_TF_DESTROY_FAILS=1
  expect destroy-fails "a failed terraform destroy fails the run" "$(output_has destroy-fails 'Error: the destroy failed')"

  # 5. An interrupted apply left a lock: --force-unlock removes it before the destroy.
  DESTROY_ARGS=(--force-unlock 22222222-2222-2222-2222-222222222222)
  run_case lock 0
  DESTROY_ARGS=()
  expect lock "the lock is released before terraform destroy" \
    "$(ordered lock 'terraform .*force-unlock -force 22222222' 'terraform .*destroy')"
  if bash "$WORK/repo/scripts/destroy.sh" --subscription "$SUB" --force-unlock "not-a-lock-id" >/dev/null 2>&1; then
    echo "FAIL lock: a lock ID that is not a UUID must be refused"
    FAILED=1
  else
    echo "PASS lock: a lock ID that is not a UUID is refused"
  fi

  # 6. Another active subscription: refused before anything runs.
  rc=0
  mkdir -p "$WORK/state"
  rm -f "$WORK/state"/*
  env PATH="$WORK/bin:$PATH" FAKE_STATE="$WORK/state" TF_STATE_STORAGE_ACCOUNT=tx02v2tfstate0123abcd \
    bash "$WORK/repo/scripts/destroy.sh" --subscription 11111111-1111-1111-1111-111111111111 >"$WORK/other.out" 2>&1 || rc=$?
  if [[ "$rc" != 0 ]] && ! grep -q 'terraform' "$WORK/state/calls.log"; then
    echo "PASS other-subscription: the active subscription must be the one named, and nothing ran"
  else
    echo "FAIL other-subscription: a run against another active subscription must stop before terraform"
    FAILED=1
  fi

  exit "$FAILED"
}

main "$@"
