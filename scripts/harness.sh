#!/usr/bin/env bash
# tx02v2 harness: every check lives here. `make` targets and every CI job only call this script.
# Usage: scripts/harness.sh <stage>...   stages: static, test, e2e, all (= static test e2e), list
#   HARNESS_STRICT=1   (set in CI) turns every SKIP into a FAIL
#   HARNESS_VERBOSE=1  also prints the output of passing checks
#   HARNESS_WORK_DIR   scratch dir for Terraform data, logs and caches (default: $TMPDIR/tx02v2-harness)
#   HARNESS_ONLY       extended regex: run only the matching checks (local debugging; never in CI)
# Prints "PASS|FAIL|SKIP <check> (<secs>s)" per check and a summary; exits 1 on any FAIL.
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/tools.sh
source "$REPO_ROOT/scripts/lib/tools.sh"
# shellcheck source=scripts/lib/platform.sh
source "$REPO_ROOT/scripts/lib/platform.sh"

export PATH="$REPO_ROOT/.tools/bin:$PATH"
export TFLINT_PLUGIN_DIR="$REPO_ROOT/.tools/tflint-plugins"
export TF_IN_AUTOMATION=1 TF_INPUT=0 CHECKPOINT_DISABLE=1
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"

HARNESS_STRICT="${HARNESS_STRICT:-0}"
HARNESS_VERBOSE="${HARNESS_VERBOSE:-0}"
HARNESS_WORK_DIR="${HARNESS_WORK_DIR:-${TMPDIR:-/tmp}/tx02v2-harness}"
HARNESS_ONLY="${HARNESS_ONLY:-}"

# Pinned schema sources of kubeconform (same pins as tx01v2; update procedure: docs/SUSTENTACAO.md).
K8S_SCHEMA_KUBERNETES_VERSION="1.36.0"
K8S_SCHEMA_REF="5f1fa4f7908afc9b6641c62d282a4a22437626e1" # yannh/kubernetes-json-schema
# datreeio/CRDs-catalog at 2026-06-02: its next revision of external-secrets.io/clustersecretstore_v1.json
# (b7e2015, 2026-10-08) cannot be compiled by kubeconform ("could not find schema"); see docs/HARNESS.md.
CRD_SCHEMA_REF="f3e4382095909ac60000da025f323ba44d4c738a"
# Scanner ignores must be reviewed at least every ~7 months.
TRIVYIGNORE_MAX_DAYS=214
ALB_CHART_OCI="oci://mcr.microsoft.com/application-lb/charts/alb-controller"
ESO_CHART_REPO="https://charts.external-secrets.io"

# Placeholder inputs used to render platform/manifests (never real identifiers).
RENDER_VAULT_URI="https://tx02v2-lab-00000000.vault.azure.net/"
RENDER_DEPLOYERS=(00000000-0000-0000-0000-000000000000 11111111-1111-1111-1111-111111111111)
RENDER_AGC_SUBNET_CIDR="10.20.4.0/24"

# Contract v4 (docs/CONTRATO.md): the App Configuration keys under tx02v2/lab/ that dx02v2 reads.
CONTRACT_KEYS=(
  location resource-group cluster-name vnet-cidr agc-subnet-cidr postgres-subnet-cidr acr/login-server
  keyvault/uri db/secret-name app/admin-token-secret-name eso/cluster-secret-store agc/id agc/frontend-name
  dns/hostname dns/acme-email waf/policy-id deploy/principal-id
)
# Contract v3: rules of the Role dx02v2-deployer, one "apiGroup|resource|verbs" per resource
# (verbs sorted). The ALB Controller 1.12.2 CRDs use singular-looking plurals on purpose.
ROLE_CRUD="create,delete,get,list,patch,update,watch"
ROLE_READ="get,list,watch"
CONTRACT_ROLE_RULES=(
  "apps|deployments|$ROLE_CRUD" "apps|replicasets|$ROLE_READ"
  "|services|$ROLE_CRUD" "|configmaps|$ROLE_CRUD" "|serviceaccounts|$ROLE_CRUD"
  "|pods|$ROLE_READ" "|pods/log|$ROLE_READ" "|events|$ROLE_READ" "|endpoints|$ROLE_READ" "|secrets|$ROLE_READ"
  "networking.k8s.io|networkpolicies|$ROLE_CRUD"
  "networking.istio.io|destinationrules|$ROLE_CRUD" "security.istio.io|authorizationpolicies|$ROLE_CRUD"
  "gateway.networking.k8s.io|gateways|$ROLE_CRUD" "gateway.networking.k8s.io|httproutes|$ROLE_CRUD"
  "alb.networking.azure.io|healthcheckpolicy|$ROLE_CRUD" "alb.networking.azure.io|webapplicationfirewallpolicy|$ROLE_CRUD"
  "autoscaling|horizontalpodautoscalers|$ROLE_CRUD" "policy|poddisruptionbudgets|$ROLE_CRUD"
  "external-secrets.io|externalsecrets|$ROLE_CRUD"
)

# Azure built-in role definition IDs: public constants, the same in every tenant (verified
# 2026-10-11 on learn.microsoft.com). The only real-looking GUIDs policy-identifiers accepts;
# terraform/modules/role-ids must agree with this table, name by name. Owner, User Access
# Administrator, Contributor and Role Based Access Control Administrator appear only in tests
# (to prove the ABAC condition excludes them) and in terraform/bootstrap by name.
declare -A BUILTIN_ROLE_IDS=(
  [516239f1-63e1-4d78-a4de-a74fb236a071]="App Configuration Data Reader"
  [5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b]="App Configuration Data Owner"
  [fbc52c3f-28ad-4303-a892-8a056630b8f1]="AppGw for Containers Configuration Manager"
  [4abbcc35-e782-43d8-92c5-2d3f1bd2253f]="Azure Kubernetes Service Cluster User Role"
  [b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b]="Azure Kubernetes Service RBAC Cluster Admin"
  [b93aa761-3e63-49ed-ac28-beffa264f7ac]="Container Registry Repository Reader"
  [2a1e307c-b015-4ebd-883e-5b7698a07328]="Container Registry Repository Writer"
  [b24988ac-6180-42a0-ab88-20f7382dd24c]="Contributor"
  [4633458b-17de-408a-b874-0445c86b69e6]="Key Vault Secrets User"
  [b86a8fe4-44ce-4948-aee5-eccb2c155cd7]="Key Vault Secrets Officer"
  [f1a07417-d97a-45cb-824c-7a7467783830]="Managed Identity Operator"
  [3913510d-42f4-4e42-8a64-420c390055eb]="Monitoring Metrics Publisher"
  [4d97b98b-1d4f-4787-a291-c67834d212e7]="Network Contributor"
  [8e3af657-a8ff-443c-a75c-2fe8c4bcb635]="Owner"
  [acdd72a7-3385-48ef-bd42-f606fba81ae7]="Reader"
  [f58310d9-a9f6-439a-9e8d-f62e7b41a168]="Role Based Access Control Administrator"
  [ba92f5b4-2d11-453d-a403-e96b0029c9fe]="Storage Blob Data Contributor"
  [2a2b9908-6ea1-4ae2-8e65-a410df84e7d1]="Storage Blob Data Reader"
  [18d7d88d-d35e-4fb5-a5c3-7773c20a72d9]="User Access Administrator"
)

REQUIRED_FILES=(
  README.md README.pt-BR.md AGENTS.md CLAUDE.md CONTRIBUTING.md SECURITY.md CHANGELOG.md LICENSE FORK.md
  .editorconfig .gitattributes .gitignore .pre-commit-config.yaml Makefile .tflint.hcl .trivyignore.yaml
  .devcontainer/devcontainer.json
  .github/CODEOWNERS .github/dependabot.yml .github/pull_request_template.md
  .github/ISSUE_TEMPLATE/config.yml .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/cloud_run_report.yml
  .github/workflows/ci.yml .github/workflows/terraform-plan.yml .github/workflows/terraform-apply.yml
  .github/workflows/platform.yml .github/workflows/terraform-destroy.yml .github/rulesets/main.json
  docs/SUSTENTACAO.md docs/GUARDRAILS.md docs/HARNESS.md docs/CONTRATO.md docs/RUNBOOK.md
  docs/ARQUITETURA.md docs/PUBLICACAO.md docs/CUSTOS.md docs/LICOES_APRENDIDAS.md
  tools/versions.env tools/checksums.txt
  scripts/install-tools.sh scripts/update-tool-checksums.sh scripts/harness.sh scripts/repo-guardrails.sh scripts/leftovers.sh
  scripts/destroy.sh scripts/tests/destroy-flow.sh scripts/tests/leftovers-flow.sh scripts/tests/local-preflight.sh
  scripts/tests/cloud-install.sh scripts/tests/image-admission.sh
  scripts/lib/common.sh scripts/lib/tools.sh scripts/lib/azure.sh
  platform/install.sh platform/uninstall.sh platform/render-manifests.sh platform/versions.env
  scripts/lib/platform.sh scripts/platform-sizing.sh scripts/platform-sizing.awk
  platform/values/alb-controller.yaml platform/values/external-secrets.yaml
  platform/full/charts.txt platform/values/full/istiod.yaml platform/values/full/otel-collector.yaml
  platform/values/full/kube-prometheus-stack.yaml platform/values/full/kube-prometheus-stack-slack.yaml
  platform/values/full/kube-prometheus-stack-storage.yaml platform/values/full/loki.yaml platform/values/full/tempo.yaml
  platform/values/full/gatekeeper.yaml platform/values/full/kyverno.yaml platform/values/full/trivy-operator.yaml platform/values/full/velero.yaml
  platform/manifests/full/argocd-platform.yaml platform/manifests/full/namespaces.yaml
  platform/manifests/full/rbac-argocd-deployer.yaml platform/manifests/full/tracing.yaml
  platform/manifests/full/waypoint.yaml platform/manifests/full/app-security.yaml
  platform/manifests/full/app-monitoring.yaml platform/manifests/full/image-verification.yaml
  platform/templates/edge-acme.yaml platform/render-edge-acme.sh
  platform/gitops/Chart.yaml platform/gitops/values.yaml
  platform/gitops/templates/application.yaml platform/gitops/templates/appproject.yaml
  platform/full/policies/constraints/allowed-repos.yaml platform/full/policies/tests/pod-acr.yaml
  platform/full/policies/tests/pod-other-region.yaml platform/full/policies/tests/suite.yaml
  terraform/modules/velero/main.tf terraform/modules/velero/variables.tf terraform/modules/velero/outputs.tf terraform/modules/velero/versions.tf
  terraform/bootstrap/.terraform.lock.hcl terraform/envs/lab/.terraform.lock.hcl
  terraform/bootstrap/terraform.tfvars.example terraform/envs/lab/terraform.tfvars.example
  terraform/envs/lab/backend.hcl.example terraform/tests/mocks/azurerm.tfmock.hcl
  terraform/modules/role-ids/main.tf
  docs/LAB_LOCAL.md
  terraform/envs/local/.terraform.lock.hcl terraform/envs/local/kind-config.yaml
  scripts/local-lab.sh scripts/leftovers-local.sh scripts/local/kind-cluster.sh scripts/lib/local.sh
  platform/local/install.sh platform/local/uninstall.sh platform/local/check.sh platform/local/versions.env
  platform/local/policies/README.md platform/local/policies/tests/suite.yaml
)
# Charts of the local platform (keys of platform/local/versions.env and platform/versions.env):
# <repo key> <version key> <sha256 key> <chart> <values files under platform/local/values, comma separated>
LOCAL_CHARTS=(
  "ISTIO_REPO ISTIO_VERSION ISTIO_BASE_SHA256 base istio-base"
  "ISTIO_REPO ISTIO_VERSION ISTIOD_SHA256 istiod istiod"
  "ISTIO_REPO ISTIO_VERSION ISTIO_CNI_SHA256 cni istio-cni"
  "ISTIO_REPO ISTIO_VERSION ZTUNNEL_SHA256 ztunnel ztunnel"
  "CERT_MANAGER_REPO CERT_MANAGER_VERSION CERT_MANAGER_SHA256 cert-manager cert-manager"
  "ESO_REPO ESO_CHART_VERSION ESO_SHA256 external-secrets ../../values/external-secrets,external-secrets"
  "METRICS_SERVER_REPO METRICS_SERVER_VERSION METRICS_SERVER_SHA256 metrics-server metrics-server"
  "KPS_REPO KPS_VERSION KPS_SHA256 kube-prometheus-stack kube-prometheus-stack"
  "GRAFANA_REPO LOKI_VERSION LOKI_SHA256 loki loki"
  "GRAFANA_REPO ALLOY_VERSION ALLOY_SHA256 alloy alloy"
  "GRAFANA_COMMUNITY_REPO TEMPO_VERSION TEMPO_SHA256 tempo tempo"
  "OTEL_COLLECTOR_REPO OTEL_COLLECTOR_CHART_VERSION OTEL_COLLECTOR_CHART_SHA256 opentelemetry-collector otel-collector"
  "ARGOCD_REPO ARGOCD_VERSION ARGOCD_SHA256 argo-cd argo-cd"
  "GATEKEEPER_REPO GATEKEEPER_VERSION GATEKEEPER_SHA256 gatekeeper gatekeeper"
  "TRIVY_OPERATOR_REPO TRIVY_OPERATOR_VERSION TRIVY_OPERATOR_SHA256 trivy-operator trivy-operator"
  "VELERO_REPO VELERO_VERSION VELERO_SHA256 velero velero"
  "CHAOS_MESH_REPO CHAOS_MESH_VERSION CHAOS_MESH_SHA256 chaos-mesh chaos-mesh"
)

# ---------------------------------------------------------------------------------------------
# Check registry and helpers
# ---------------------------------------------------------------------------------------------

declare -a CHECK_STAGE=() CHECK_NAME=() CHECK_CMD=()
register() {
  CHECK_STAGE+=("$1")
  CHECK_NAME+=("$2")
  CHECK_CMD+=("$3")
}

strict() { [[ "$HARNESS_STRICT" == 1 ]]; }

# skip REASON -> ends the current check as SKIP (FAIL in strict mode). Only for missing preconditions.
# Exit code 77 (the automake SKIP convention) never collides with the tools' own codes.
SKIP_CODE=77
skip() {
  printf 'SKIP_REASON: %s\n' "$*"
  exit "$SKIP_CODE"
}

need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || skip "'$c' not found (run: make tools)"
  done
}

# visible_files -> files git would track (tracked + untracked, minus .gitignore), one per line.
visible_files() {
  git ls-files --cached --others --exclude-standard
}

# tf_files -> every Terraform configuration file (no tests, no provider caches), sorted.
tf_files() {
  find terraform -name '*.tf' -not -path '*/.terraform/*' | sort
}

# matches GREP_ARGS... -> grep, where "no match" (status 1) is not an error but status >= 2 is.
matches() {
  local status=0
  grep "$@" || status=$?
  ((status <= 1)) || {
    echo "grep failed with status $status" >&2
    return "$status"
  }
}

# is_placeholder_guid GUID -> success for a GUID made of one repeated hex digit (0000..., dddd...).
is_placeholder_guid() {
  local s="${1//-/}"
  [[ ${#s} == 32 && -z "${s//"${s:0:1}"/}" ]]
}

# forbid REGEX MESSAGE GLOB PATH... -> fails when the extended regex matches in the files named
# GLOB ('*' for all) under PATH (recursive).
forbid() {
  local re=$1 msg=$2 glob=$3 out status=0
  shift 3
  out="$(grep -rnIE --include="$glob" -e "$re" -- "$@")" || status=$?
  ((status <= 1)) || {
    echo "grep failed with status $status"
    return 1
  }
  if [[ -n "$out" ]]; then
    printf 'forbidden: %s\n%s\n' "$msg" "$out"
    return 1
  fi
}

date_plus_days() {
  date -u -d "+$1 days" +%F 2>/dev/null || date -u -v+"$1"d +%F
}

# platform_versions -> fills the associative array PV with platform/versions.env (not executed).
declare -A PV=()
platform_versions() {
  local key value
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z0-9_]+$ ]] && PV[$key]="$value"
  done < <(grep -E '^[A-Z0-9_]+=' platform/versions.env)
}

tf_init() {
  local dir=$1
  local -a args=(-backend=false -input=false -no-color)
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  export TF_DATA_DIR="$HARNESS_WORK_DIR/terraform/${dir//\//_}"
  # Root configurations must resolve providers from their committed lock file only.
  [[ -f "$dir/.terraform.lock.hcl" && "$dir" != terraform/modules/* ]] && args+=(-lockfile=readonly)
  terraform -chdir="$dir" init "${args[@]}"
}

# render_platform -> platform/manifests rendered with the placeholder inputs.
render_platform() {
  local IFS=,
  bash platform/render-manifests.sh "$RENDER_VAULT_URI" "${RENDER_DEPLOYERS[*]}"
}

# render_platform_full -> cloud manifests plus full GitOps resources, with synthetic fork values.
render_platform_full() {
  local IFS=,
  bash platform/render-manifests.sh "$RENDER_VAULT_URI" "${RENDER_DEPLOYERS[*]}" \
    --full maringelix --acr-login-server tx02v2labb602d594.azurecr.io --agc-subnet-cidr "$RENDER_AGC_SUBNET_CIDR"
}

# kubectl_local FILE GO_TEMPLATE -> evaluates the template on every object of FILE without any
# cluster (kubectl annotate --local parses the YAML; nothing is sent anywhere).
kubectl_local() {
  KUBECONFIG=/dev/null kubectl annotate --local -f "$1" harness.tx02v2/parsed=true --overwrite -o go-template="$2"
}

installed_version() {
  local out=""
  case "$1" in
    terraform) out="$(terraform version 2>/dev/null)" || out="" ;;
    tflint) out="$(tflint --version 2>/dev/null)" || out="" ;;
    trivy) out="$(trivy --version 2>/dev/null)" || out="" ;;
    actionlint) out="$(actionlint -version 2>/dev/null)" || out="" ;;
    shellcheck) out="$(shellcheck --version 2>/dev/null)" || out="" ;;
    kubeconform) out="$(kubeconform -v 2>/dev/null)" || out="" ;;
    gitleaks) out="$(gitleaks version 2>/dev/null)" || out="" ;;
    kubectl) out="$(kubectl version --client 2>/dev/null)" || out="" ;;
    helm) out="$(helm version --short 2>/dev/null)" || out="" ;;
    kubelogin) out="$(kubelogin --version 2>/dev/null)" || out="" ;;
    kind) out="$(kind version 2>/dev/null)" || out="" ;;
    gator) out="$(gator --version 2>/dev/null)" || out="" ;;
  esac
  [[ "$out" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# ---------------------------------------------------------------------------------------------
# Checks (each runs in its own subshell from the repository root)
# ---------------------------------------------------------------------------------------------

check_tool_versions() {
  local t want got
  local -a missing=() mismatch=()
  load_versions
  for t in "${TOOLS_ALL[@]}"; do
    want="$(tool_version "$t")"
    if tool_is_plugin "$t"; then
      if [[ -x "$(tool_installed_path "$t" "$want" "$REPO_ROOT/.tools")" ]]; then
        printf '%-24s %s (plugin)\n' "$t" "$want"
      else
        missing+=("$t")
      fi
      continue
    fi
    if ! command -v "$t" >/dev/null 2>&1; then
      missing+=("$t")
      continue
    fi
    got="$(installed_version "$t")"
    printf '%-24s want %-8s got %-8s %s\n' "$t" "$want" "${got:-?}" "$(command -v "$t")"
    [[ "$got" == "$want" ]] || mismatch+=("$t")
  done
  ((${#missing[@]} == 0)) || skip "missing tools: ${missing[*]} (run: make tools)"
  if ((${#mismatch[@]} > 0)); then
    strict && {
      echo "versions differ from tools/versions.env: ${mismatch[*]}"
      return 1
    }
    skip "versions differ from tools/versions.env: ${mismatch[*]} (run: make tools)"
  fi
}

check_repo_structure() {
  local f d rc=0 image out
  local -a untracked=()
  for f in "${REQUIRED_FILES[@]}"; do
    [[ -f "$f" ]] || {
      echo "missing required file: $f"
      rc=1
    }
  done
  if [[ -f CLAUDE.md ]]; then
    [[ "$(sed -n 1p CLAUDE.md)" == "@AGENTS.md" ]] || {
      echo "CLAUDE.md: the first line must be @AGENTS.md"
      rc=1
    }
    (($(grep -c . CLAUDE.md) == 2)) || {
      echo "CLAUDE.md: must contain exactly @AGENTS.md and one sentence"
      rc=1
    }
  fi
  if [[ -f README.md ]] && (($(wc -l <README.md) > 250)); then
    echo "README.md: more than 250 lines"
    rc=1
  fi
  for f in README.md README.pt-BR.md; do
    [[ -f "$f" ]] || continue
    forbid 'production-grade|production-ready|enterprise|best-in-class|world-class' "self-ratings in $f" '*' "$f" || rc=1
    # v1 repositories are private or archived: never link them (tx01v2-style names end in v2).
    forbid 'github\.com/maringelix/(tx|dx)0[0-9]([^0-9v]|$)' "links to v1 repositories in $f" '*' "$f" || rc=1
    grep -qP 'x' <<<"x" 2>/dev/null || skip "grep -P (PCRE) is not available"
    out="$(LC_ALL=C.UTF-8 matches -nP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B50}\x{2705}]' "$f")" || return 1
    [[ -z "$out" ]] || {
      printf '%s: emojis are not allowed:\n%s\n' "$f" "$out"
      rc=1
    }
  done
  if [[ -f README.md ]] && ! grep -qF 'not run in the cloud (v2)' README.md; then
    echo "README.md: the status matrix must use the label 'not run in the cloud (v2)'"
    rc=1
  fi
  if [[ -f README.pt-BR.md ]] && ! grep -qF 'não executado em nuvem (v2)' README.pt-BR.md; then
    echo "README.pt-BR.md: the status matrix must use the label 'não executado em nuvem (v2)'"
    rc=1
  fi
  for d in terraform/modules/*/; do
    grep -q 'required_providers' "${d}versions.tf" 2>/dev/null || {
      echo "${d}versions.tf: missing required_providers"
      rc=1
    }
  done
  if [[ -f .devcontainer/devcontainer.json ]]; then
    image="$(grep -E '^[[:space:]]*"image":' .devcontainer/devcontainer.json || :)"
    [[ "$image" =~ @sha256:[0-9a-f]{64}\" ]] || {
      echo ".devcontainer/devcontainer.json: the base image must be pinned by digest (@sha256:...)"
      rc=1
    }
    grep -qE '"postCreateCommand":[[:space:]]*"make tools"' .devcontainer/devcontainer.json || {
      echo ".devcontainer/devcontainer.json: postCreateCommand must be \"make tools\""
      rc=1
    }
    if grep -nE '"ghcr.io/devcontainers/features/[^"@]+"' .devcontainer/devcontainer.json | grep -v '@sha256:'; then
      echo ".devcontainer/devcontainer.json: features must be pinned by digest"
      rc=1
    fi
  fi
  need git
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -q $'\r' "$f"; then
      echo "CRLF line endings (LF required): $f"
      rc=1
    fi
  done < <(visible_files)
  # Entry-point scripts must keep the executable bit in git (commits from Windows can drop it).
  while IFS= read -r f; do
    if [[ -z "$(git ls-files -- "$f")" ]]; then
      untracked+=("$f")
    elif [[ "$(git ls-files -s -- "$f" | awk '{ print $1 }')" != 100755 ]]; then
      echo "not executable in the git index (git update-index --chmod=+x $f): $f"
      rc=1
    fi
  done < <(visible_files | grep -E '^(scripts|platform)/[^/]+\.sh$' | sort)
  if ((${#untracked[@]} > 0)); then
    echo "note: not tracked yet, add them with the executable bit: git add --chmod=+x ${untracked[*]}"
  fi
  return "$rc"
}

check_version_consistency() {
  local rc=0 v alb k8s_minor eso actions
  load_versions
  platform_versions
  v="$(awk '/^plugin "azurerm"/ { a = 1 } a && /^[[:space:]]*version[[:space:]]*=/ { gsub(/[" ]/, ""); sub(/^version=/, ""); print; exit }' .tflint.hcl)"
  [[ "$v" == "$TFLINT_RULESET_AZURERM_VERSION" ]] || {
    echo ".tflint.hcl uses tflint-ruleset-azurerm $v but tools/versions.env pins $TFLINT_RULESET_AZURERM_VERSION"
    rc=1
  }
  v="$(sed -n 's/.*rev: [0-9a-f]\{40\} # frozen: v\([0-9.]*\)$/\1/p' <(grep -A1 'gitleaks/gitleaks' .pre-commit-config.yaml))"
  [[ "$v" == "$GITLEAKS_VERSION" ]] || {
    echo ".pre-commit-config.yaml pins the gitleaks hook at '${v:-?}' but tools/versions.env pins $GITLEAKS_VERSION"
    rc=1
  }
  alb="${PV[ALB_CONTROLLER_CHART_VERSION]:-}"
  [[ "$alb" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "platform/versions.env: ALB_CONTROLLER_CHART_VERSION is missing or malformed"
    rc=1
  }
  grep -qE "^    tag: \"${alb//./\\.}\"$" platform/values/alb-controller.yaml || {
    echo "platform/values/alb-controller.yaml: albController.image.tag must equal the chart version $alb"
    rc=1
  }
  eso="${PV[ESO_CHART_VERSION]:-}"
  (($(grep -cE "tag: v${eso//./\\.}@sha256:[0-9a-f]{64}$" platform/values/external-secrets.yaml) == 3)) || {
    echo "platform/values/external-secrets.yaml must pin the three images to v${eso:-?} by digest"
    rc=1
  }
  (($(grep -h 'required_version' terraform/*/versions.tf terraform/*/*/versions.tf | sort -u | wc -l) == 1)) || {
    echo "every versions.tf must use the same required_version"
    rc=1
  }
  (($(grep -h -A1 'source  = "hashicorp/azurerm"' terraform/*/versions.tf terraform/*/*/versions.tf | grep version | sort -u | wc -l) == 1)) || {
    echo "every versions.tf must use the same hashicorp/azurerm constraint"
    rc=1
  }
  [[ "$(grep -A1 'hashicorp/azurerm"' terraform/bootstrap/.terraform.lock.hcl | grep version)" == "$(grep -A1 'hashicorp/azurerm"' terraform/envs/lab/.terraform.lock.hcl | grep version)" ]] || {
    echo "bootstrap and envs/lab must lock the same hashicorp/azurerm version"
    rc=1
  }
  # kubeconform validates the platform manifests for the Kubernetes minor the lab runs.
  k8s_minor="$(awk '/^variable "kubernetes_version"/ { a = 1 } a && /^[[:space:]]*default[[:space:]]*=/ { gsub(/[" ]/, ""); sub(/^default=/, ""); print; exit }' terraform/envs/lab/variables.tf)"
  [[ "$K8S_SCHEMA_KUBERNETES_VERSION" == "$k8s_minor."* ]] || {
    echo "kubernetes_version defaults to $k8s_minor but kubeconform validates against $K8S_SCHEMA_KUBERNETES_VERSION (scripts/harness.sh)"
    rc=1
  }
  # One SHA per action across every workflow (Dependabot bumps them together).
  actions="$(awk '
    match($0, /uses: [A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]+/) {
      s = substr($0, RSTART + 6, RLENGTH - 6); split(s, p, "@")
      if (!((p[1], p[2]) in seen)) { seen[p[1], p[2]] = 1; n[p[1]]++; l[p[1]] = l[p[1]] " " p[2] }
    }
    END { for (a in n) if (n[a] > 1) print a ":" l[a] }
  ' .github/workflows/*.yml)"
  [[ -z "$actions" ]] || {
    printf 'the same action is pinned to different commits:\n%s\n' "$actions"
    rc=1
  }
  return "$rc"
}

check_terraform_fmt() {
  need terraform
  terraform fmt -check -recursive -diff -no-color terraform
}

check_terraform_validate() {
  need terraform
  tf_init "$1"
  terraform -chdir="$1" validate -no-color
}

check_terraform_lockfiles() {
  local f rc=0
  for f in terraform/bootstrap/.terraform.lock.hcl terraform/envs/lab/.terraform.lock.hcl terraform/envs/local/.terraform.lock.hcl; do
    awk -v file="$f" '
      /^provider "/ { name = $2; h1 = 0; next }
      /"h1:/ { h1++ }
      /^}/ && name != "" { printf "%s %s: %d platform hashes (h1)\n", file, name, h1; if (h1 < 4) bad = 1; name = "" }
      END { exit bad }
    ' "$f" || {
      echo "$f: every provider needs h1 hashes for linux_amd64, linux_arm64, darwin_arm64 and windows_amd64"
      echo "fix: terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=windows_amd64"
      rc=1
    }
  done
  return "$rc"
}

# Block-aware rules over every *.tf (terraform fmt layout: top-level blocks open at column 0,
# their arguments are indented by exactly two spaces). Prints one "file:line: message" per violation.
policy_terraform_blocks() {
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function value(s) {
      sub(/^[^=]*=[[:space:]]*/, "", s)
      if (s ~ /^"/) { match(s, /^"[^"]*"/); return substr(s, RSTART, RLENGTH) }
      sub(/[[:space:]].*$/, "", s)
      return s
    }
    function err(line, msg) { printf "%s:%d: %s\n", file, line, msg; bad = 1 }
    function arg(n) { return (n in args) ? args[n] : "" }
    function reset() {
      inblock = 0; kind = ""; btype = ""; bname = ""; top = ""; nts = 0; collecting = 0
      ignore_all = 0; backend = ""
      split("", args); split("", argline); split("", ignored); split("", bargs)
    }
    function end_block(   i, a, id) {
      id = btype "." bname
      if (kind == "resource") {
        for (a in args)
          if (a ~ /^(password|admin_password|administrator_password|administrator_login_password|secret_string|client_secret)$/)
            err(argline[a], id " sets " a " in plain text: use the write-only " a "_wo with an ephemeral value")
        if (btype == "azurerm_key_vault_secret" && ("value" in args))
          err(argline["value"], id ": secret values only through value_wo (write-only, never in plan or state)")
        if (btype == "azurerm_postgresql_flexible_server") {
          if (arg("public_network_access_enabled") != "false") err(bline, id ": PostgreSQL must set public_network_access_enabled = false (private access only)")
          if (arg("create_mode") == "\"Replica\"") {
            if (!("source_server_id" in args)) err(bline, id ": a replica must name its source_server_id and inherit credentials")
          } else if (!("administrator_password_wo" in args)) err(bline, id ": the admin password must be set with administrator_password_wo")
        }
        if (btype == "azurerm_postgresql_flexible_server_firewall_rule") err(bline, id ": no PostgreSQL firewall rules (private access only)")
        if (btype == "azurerm_storage_account" && arg("shared_access_key_enabled") != "false") err(bline, id ": storage accounts must set shared_access_key_enabled = false (Entra ID only)")
        if (btype == "azurerm_container_registry" && arg("admin_enabled") != "false") err(bline, id ": the registry must set admin_enabled = false")
        if (btype == "azurerm_container_registry" && ("anonymous_pull_enabled" in args) && arg("anonymous_pull_enabled") != "false") err(bline, id ": anonymous pull must stay off")
        if (btype == "azurerm_kubernetes_cluster" && arg("local_account_disabled") != "true") err(bline, id ": AKS must set local_account_disabled = true (Entra ID only)")
        if (btype == "azurerm_kubernetes_cluster" && arg("azure_policy_enabled") == "true") err(argline["azure_policy_enabled"], id ": no Azure Policy add-on (cost; v1 fought Gatekeeper with it)")
        if (btype == "azurerm_key_vault" && arg("rbac_authorization_enabled") != "true") err(bline, id ": Key Vault must set rbac_authorization_enabled = true")
        if (btype == "azurerm_app_configuration" && arg("local_auth_enabled") != "false") err(bline, id ": App Configuration must set local_auth_enabled = false (Entra ID only)")
        # The local lab (terraform/envs/local) keeps throwaway credentials of this machine in its local
        # state on purpose: the platform scripts read them back. Every cloud root uses ephemeral resources.
        if (btype ~ /^random_(password|string)$/ && file !~ /^terraform\/envs\/local\//) err(bline, id ": generated secrets must be ephemeral resources (a random_password resource stores its result in state)")
        if (btype == "azurerm_resource_provider_registration") err(bline, id ": register resource providers with the provider argument resource_providers_to_register (this resource fails when already registered and unregisters on destroy)")
        for (i = 1; i <= nts; i++)
          if (!ignore_all && !(tsattr[i] in ignored))
            err(tsline[i], id ": timestamp()/plantimestamp() in " tsattr[i] " without lifecycle { ignore_changes = [" tsattr[i] "] } (perpetual diff)")
      } else {
        for (i = 1; i <= nts; i++) err(tsline[i], "timestamp()/plantimestamp() outside a resource with lifecycle.ignore_changes (perpetual diff)")
      }
      if (kind == "provider" && bname == "azurerm") {
        if (arg("resource_provider_registrations") != "\"none\"") err(bline, "provider azurerm: set resource_provider_registrations = \"none\" (bootstrap registers the lab providers)")
        if (arg("storage_use_azuread") != "true") err(bline, "provider azurerm: set storage_use_azuread = true (shared keys are disabled)")
        for (a in args)
          if (a ~ /^(client_secret|client_certificate|client_certificate_password|client_certificate_path|use_cli|use_msi|use_oidc|oidc_token)$/)
            err(argline[a], "provider azurerm: " a " must not be set in code (credentials come from ARM_* / the Azure CLI)")
      }
      if (kind == "provider" && bname ~ /^(kubernetes|helm|azuread)$/) err(bline, "provider " bname ": not allowed (platform/install.sh talks to Kubernetes; managed identities need no Entra directory access)")
      if (kind == "terraform" && backend == "azurerm") {
        if (bargs["use_azuread_auth"] != "true") err(bline, "backend azurerm: set use_azuread_auth = true (the state account has shared keys disabled)")
        for (a in bargs)
          if (a ~ /^(access_key|sas_token|client_secret|use_cli|use_msi|use_oidc)$/) err(bline, "backend azurerm: " a " must not be set in code")
      }
      reset()
    }
    FNR == 1 { if (inblock) end_block(); reset(); file = FILENAME }
    !inblock && /^[a-z_]+([[:space:]]+"[^"]*")*[[:space:]]*\{/ {
      kind = $1; btype = ""; bname = ""
      if (kind == "resource" || kind == "data" || kind == "ephemeral") { btype = $2; bname = $3; gsub(/"/, "", btype); gsub(/"/, "", bname) }
      else if (kind == "provider" || kind == "module" || kind == "check" || kind == "variable" || kind == "output") { btype = kind; bname = $2; gsub(/"/, "", bname) }
      else btype = kind
      bline = FNR; inblock = 1
      if ($0 ~ /\{[[:space:]]*\}[[:space:]]*$/) end_block()
      next
    }
    inblock && /^\}/ { end_block(); next }
    inblock {
      line = $0
      if (line ~ /^[[:space:]]*#/) next
      if (line ~ /^  [a-z_0-9]+[[:space:]]*=/) {
        n = line; sub(/^  /, "", n); sub(/[[:space:]]*=.*$/, "", n)
        args[n] = value(line); argline[n] = FNR; top = n
      } else if (line ~ /^  dynamic[[:space:]]+"[a-z_0-9]+"/) {
        n = line; sub(/^  dynamic[[:space:]]+"/, "", n); sub(/".*$/, "", n); top = n
      } else if (line ~ /^  [a-z_0-9]+([[:space:]]+"[^"]*")*[[:space:]]*\{/) {
        n = line; sub(/^  /, "", n); split(n, w, /[[:space:]]+/); top = w[1]
        if (kind == "terraform" && top == "backend") { backend = w[2]; gsub(/"/, "", backend) }
      }
      if (kind == "terraform" && top == "backend" && line ~ /^    [a-z_0-9]+[[:space:]]*=/) {
        n = line; sub(/^    /, "", n); sub(/[[:space:]]*=.*$/, "", n); bargs[n] = value(line)
      }
      if (top == "lifecycle" && line ~ /ignore_changes[[:space:]]*=/) { collecting = 1; ic = "" }
      if (collecting) {
        ic = ic " " line
        if (line ~ /\]/ || line ~ /=[[:space:]]*all[[:space:]]*$/) {
          collecting = 0
          if (ic ~ /=[[:space:]]*all[[:space:]]*$/) ignore_all = 1
          sub(/^[^\[]*\[/, "", ic); sub(/\].*$/, "", ic)
          cnt = split(ic, items, /,/)
          for (i = 1; i <= cnt; i++) { it = trim(items[i]); sub(/[\[.].*$/, "", it); if (it != "") ignored[it] = 1 }
        }
      }
      if (line ~ /(^|[^A-Za-z0-9_])(plan)?timestamp\(/) { nts++; tsline[nts] = FNR; tsattr[nts] = top }
    }
    END { if (inblock) end_block(); exit bad }
  ' "$@"
}

check_policy_terraform() {
  local rc=0 out
  local -a files=()
  mapfile -t files < <(tf_files)
  ((${#files[@]} > 0)) || {
    echo "no Terraform files found"
    return 1
  }
  if ! out="$(policy_terraform_blocks "${files[@]}")"; then
    printf 'forbidden by the Terraform policy:\n%s\n' "$out"
    rc=1
  fi
  forbid 'provider[[:space:]]+"(kubernetes|helm|azuread)"|hashicorp/(kubernetes|helm|azuread)|(resource|data)[[:space:]]+"azuread_' \
    "no kubernetes, helm or azuread providers (platform/install.sh talks to Kubernetes; identities are managed identities)" '*.tf' terraform || rc=1
  forbid '^[^#]*"(Owner|User Access Administrator)"|8e3af657-a8ff-443c-a75c-2fe8c4bcb635|18d7d88d-d35e-4fb5-a5c3-7773c20a72d9' \
    "the Owner and User Access Administrator roles are never assigned (the ABAC condition of tx02v2-gha-apply excludes them)" '*.tf' terraform || rc=1
  forbid '^[^#]*shared_access_key_enabled[[:space:]]*=[[:space:]]*true|^[^#]*admin_enabled[[:space:]]*=[[:space:]]*true|^[^#]*local_account_disabled[[:space:]]*=[[:space:]]*false' \
    "shared keys, the ACR admin user and AKS local accounts stay disabled" '*.tf' terraform || rc=1
  # Role assignments, locks and custom roles are scoped to the lab resource group or below.
  forbid '^[[:space:]]*scope[[:space:]]*=.*[Ss]ubscription' \
    "nothing at subscription scope: scope role assignments to tx02v2-lab or a resource inside it" '*.tf' terraform || rc=1
  forbid '^[^#]*data[[:space:]]+"azurerm_subscription"' \
    "the lab root never reads or targets the subscription" '*.tf' terraform/envs terraform/modules || rc=1
  forbid 'hashicorp/(aws|azurerm|google)|provider[[:space:]]+"(aws|azurerm|google)"|backend[[:space:]]+"(s3|azurerm|gcs)"' \
    "the local lab must not reach a cloud (no cloud provider or remote backend in terraform/envs/local)" '*.tf' terraform/envs/local || rc=1
  forbid '^[[:space:]]*ip[[:space:]]*=[[:space:]]*"0\.0\.0\.0"|^[[:space:]]*privileged[[:space:]]*=[[:space:]]*true' \
    "local lab containers publish ports on 127.0.0.1 only and never run privileged" '*.tf' terraform/envs/local || rc=1
  # Exercise the replica exception: it inherits the password only from a named source. The plain
  # password ban above applies equally to primary instances, replicas and future create modes.
  local fixture_dir="$HARNESS_WORK_DIR/postgres-policy-fixtures"
  mkdir -p "$fixture_dir"
  cat >"$fixture_dir/valid.tf" <<'EOF'
resource "azurerm_postgresql_flexible_server" "replica" {
  create_mode                   = "Replica"
  source_server_id              = module.postgres.server_id
  public_network_access_enabled = false
}
EOF
  if ! policy_terraform_blocks "$fixture_dir/valid.tf"; then
    echo "replica policy rejected inherited credentials from a named source"
    rc=1
  fi
  sed '/source_server_id/d' "$fixture_dir/valid.tf" >"$fixture_dir/no-source.tf"
  if policy_terraform_blocks "$fixture_dir/no-source.tf" >"$fixture_dir/no-source.log"; then
    echo "replica policy accepted a replica with no source"
    rc=1
  fi
  sed '/create_mode/a\  administrator_password = "placeholder-not-a-secret"' "$fixture_dir/valid.tf" >"$fixture_dir/plaintext.tf"
  if policy_terraform_blocks "$fixture_dir/plaintext.tf" >"$fixture_dir/plaintext.log"; then
    echo "replica policy accepted a plain text password"
    rc=1
  fi
  return "$rc"
}

# Every resource whose azurerm schema has a top-level `tags` attribute sets the contract tags
# (local.tags in the roots, var.tags in the modules): azurerm has no provider default tags.
check_policy_tags() {
  local rc=0 schema console_dir blocks types taggable out
  local -a files=()
  need terraform
  mkdir -p "$HARNESS_WORK_DIR"
  schema="$HARNESS_WORK_DIR/azurerm-schema.json"
  # bootstrap has no backend block and locks the same azurerm version as envs/lab (version-consistency).
  tf_init terraform/bootstrap >/dev/null
  terraform -chdir=terraform/bootstrap providers schema -json >"$schema"
  unset TF_DATA_DIR
  mapfile -t files < <(tf_files)
  blocks="$(awk '
    FNR == 1 { if (t != "") print f, l, t, n, tags; t = "" }
    /^resource "[a-z0-9_]+" "[^"]+"/ { t = $2; n = $3; gsub(/"/, "", t); gsub(/"/, "", n); f = FILENAME; l = FNR; tags = "-"; next }
    t != "" && /^  tags[[:space:]]*=/ { tags = $0; sub(/^  tags[[:space:]]*=[[:space:]]*/, "", tags); gsub(/[[:space:]]/, "", tags) }
    t != "" && /^\}/ { print f, l, t, n, tags; t = "" }
    END { if (t != "") print f, l, t, n, tags }
  ' "${files[@]}")"
  types="$(awk '$3 ~ /^azurerm_/ { print $3 }' <<<"$blocks" | sort -u | awk '{ printf "%s\"%s\"", (NR > 1 ? "," : ""), $1 }')"
  [[ -n "$types" ]] || {
    echo "no azurerm resources found"
    return 1
  }
  console_dir="$(mktemp -d "$HARNESS_WORK_DIR/console.XXXXXX")"
  taggable="$(terraform -chdir="$console_dir" console -no-color <<EOF
join(" ", [for t in [$types] : t if contains(keys(jsondecode(file("$schema")).provider_schemas["registry.terraform.io/hashicorp/azurerm"].resource_schemas[t].block.attributes), "tags")])
EOF
  )"
  rm -rf "$console_dir"
  taggable="${taggable//\"/}"
  [[ "$taggable" =~ ^[a-z0-9_\ ]+$ ]] || {
    echo "could not read the taggable resource types from the azurerm schema: $taggable"
    return 1
  }
  out="$(awk -v taggable=" $taggable " '
    index(taggable, " " $3 " ") {
      checked++
      if ($5 == "-") { printf "%s:%s: %s.%s has no tags (contract tags on every taggable resource)\n", $1, $2, $3, $4; bad = 1 }
      else if ($5 != "local.tags" && $5 != "var.tags") { printf "%s:%s: %s.%s sets tags = %s (use local.tags in a root, var.tags in a module)\n", $1, $2, $3, $4, $5; bad = 1 }
    }
    END { printf "%d taggable resources checked\n", checked; exit bad }
  ' <<<"$blocks")" || rc=1
  printf '%s\n' "$out"
  echo "taggable types in use: $taggable"
  return "$rc"
}

check_policy_identifiers() {
  local rc=0 out guid name role_file f
  local -a files=()
  need git
  grep -qP 'x' <<<"x" 2>/dev/null || skip "grep -P (PCRE) is not available"
  # Regular files only (a symlinked .tools or a deleted tracked file is not content to scan).
  mapfile -t files < <(visible_files | grep -vE '(^|/)(\.terraform\.lock\.hcl|checksums\.txt)$' |
    while IFS= read -r f; do if [[ -f "$f" && ! -L "$f" ]]; then printf '%s\n' "$f"; fi; done)
  ((${#files[@]} > 0)) || return 0
  # Not the last group of a GUID (checked below with the other GUID rules).
  out="$(matches -noP '(?<![0-9A-Za-z-])[0-9]{12}(?![0-9A-Za-z-])' "${files[@]}" | matches -v ':123456789012$')"
  [[ -z "$out" ]] || {
    printf '12-digit account IDs must be placeholders (123456789012):\n%s\n' "$out"
    rc=1
  }
  out="$(matches -noP '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' "${files[@]}" |
    matches -vP '@(example\.(com|org|net)|users\.noreply\.github\.com)$')"
  [[ -z "$out" ]] || {
    printf 'e-mail addresses must use example.com/example.org placeholders:\n%s\n' "$out"
    rc=1
  }
  out="$(matches -noP '(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])' "${files[@]}" |
    matches -vP ':(10\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|0\.0\.0\.0)')"
  [[ -z "$out" ]] || {
    printf 'IP addresses must be private or documentation ranges (RFC 1918 / RFC 5737):\n%s\n' "$out"
    rc=1
  }
  # GUIDs: subscription, tenant, object and client IDs are placeholders made of one repeated hex
  # digit (00000000-0000-0000-0000-000000000000, 11111111-...); only the named built-in role IDs
  # of BUILTIN_ROLE_IDS are real.
  out="$(matches -noP '(?<![0-9A-Za-z-])[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}(?![0-9A-Za-z-])' "${files[@]}" |
    while IFS= read -r line; do
      guid="${line##*:}"
      is_placeholder_guid "$guid" && continue
      [[ -n "${BUILTIN_ROLE_IDS[$guid]:-}" ]] && continue
      printf '%s\n' "$line"
    done)"
  [[ -z "$out" ]] || {
    printf 'GUIDs must be placeholders (00000000-0000-0000-0000-000000000000 or another single repeated digit) or a built-in role ID listed in BUILTIN_ROLE_IDS (scripts/harness.sh):\n%s\n' "$out"
    rc=1
  }
  # The role IDs the lab may assign (and the ABAC condition allows) must be the verified constants.
  role_file=terraform/modules/role-ids/main.tf
  while IFS=$'\t' read -r name guid; do
    [[ "${BUILTIN_ROLE_IDS[$guid]:-}" == "$name" ]] || {
      echo "$role_file: \"$name\" = \"$guid\" differs from the verified built-in role IDs (BUILTIN_ROLE_IDS)"
      rc=1
    }
  done < <(sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*"([0-9a-f-]{36})"[[:space:]]*$/\1\t\2/p' "$role_file")
  (($(grep -cE '^[[:space:]]*"[^"]+"[[:space:]]*=[[:space:]]*"[0-9a-f-]{36}"' "$role_file") > 0)) || {
    echo "$role_file: no role IDs found"
    rc=1
  }
  return "$rc"
}

# scripts/destroy.sh with simulated az, terraform, kubectl and helm: an uninstall that fails still ends
# in terraform destroy (docs/GUARDRAILS.md, CUSTO-03).
check_destroy_flow() {
  bash scripts/tests/destroy-flow.sh
}

# The pre-flight of scripts/local-lab.sh with a simulated docker, kind and ip: a machine whose Docker
# CLI and provider disagree, whose network or route overlaps the lab or whose registry port is taken
# is refused, and a lab of another state directory is never touched (docs/GUARDRAILS.md, LOC-06).
check_local_preflight() {
  bash scripts/tests/local-preflight.sh
}

# scripts/leftovers.sh with a simulated az: in a subscription that also holds other work only the lab's
# resources are billable leftovers, and every az call names the subscription (SEC-14).
check_leftovers_flow() {
  bash scripts/tests/leftovers-flow.sh
}

# Scripts act only on what the lab created (docs/GUARDRAILS.md, SEC-14): no variable of the caller's
# shell chooses their target (a forker may have RESOURCE_GROUP or CLUSTER_NAME exported for another
# cluster), the cloud kubeconfig is a temporary file (kubelogin converts only that file), the cloud
# scripts check the tag Project=tx02v2 of the cluster and every script of platform/local checks the
# kind context first.
# shellcheck disable=SC2016 # the patterns and messages name shell expansions literally
check_policy_scripts() {
  local rc=0 out f
  forbid '\$\{(CLUSTER_NAME|RESOURCE_GROUP|LAB_[A-Z_]+|CONTRACT_PARAMETER)(:-|-|:=|=)' \
    "an environment variable must never choose the target of a script of the lab" '*.sh' scripts platform || rc=1
  out="$(grep -rn --include='*.sh' --exclude=harness.sh --exclude-dir=tests -e 'aks get-credentials' scripts platform | grep -v -e '--file "\$KUBECONFIG"')" || true
  [[ -z "$out" ]] || {
    printf 'az aks get-credentials must write a temporary file (--file "$KUBECONFIG"), never ~/.kube/config:\n%s\n' "$out"
    rc=1
  }
  out="$(grep -rn --include='*.sh' --exclude=harness.sh --exclude-dir=tests -e 'kubelogin convert-kubeconfig' scripts platform | grep -v -e '--kubeconfig "\$KUBECONFIG"')" || true
  [[ -z "$out" ]] || {
    printf 'kubelogin convert-kubeconfig must convert only the temporary file (--kubeconfig "$KUBECONFIG"):\n%s\n' "$out"
    rc=1
  }
  for f in platform/install.sh platform/uninstall.sh; do
    grep -q '^  require_lab_cluster ' "$f" || {
      echo "$f must call require_lab_cluster (tag Project=tx02v2) before it touches the cluster"
      rc=1
    }
  done
  for f in platform/local/install.sh platform/local/check.sh platform/local/uninstall.sh; do
    grep -q '^  require_lab_context$' "$f" || {
      echo "$f must call require_lab_context (only the kind context of the lab) before any kubectl"
      rc=1
    }
  done
  return "$rc"
}

check_tflint() {
  need tflint
  [[ -d "$TFLINT_PLUGIN_DIR/github.com/terraform-linters/tflint-ruleset-azurerm" ]] || skip "tflint-ruleset-azurerm is not installed (run: make tools)"
  (cd terraform && tflint --recursive --config "$REPO_ROOT/.tflint.hcl" --format compact --no-color)
}

trivy_config() {
  trivy config --quiet --skip-check-update --exit-code 1 --severity HIGH,CRITICAL \
    --cache-dir "$HARNESS_WORK_DIR/trivy-cache" --ignorefile .trivyignore.yaml \
    --skip-dirs .tools --skip-dirs .cache --skip-dirs '**/.terraform' \
    --skip-dirs platform/local/policies/tests --skip-dirs platform/full/policies/tests "$@"
  # The policy test directories contain intentional gator fixtures (never applied to a cluster).
  # Everything applied to a cluster is scanned.
}

check_trivy_config() {
  need trivy
  trivy_config .
}

# Same scan with the example inputs: trivy applies them to the terraform/envs/lab root, so
# variable-dependent checks (for example the authorized IP ranges) see real values.
check_trivy_config_tfvars() {
  need trivy
  trivy_config --tf-vars terraform/envs/lab/terraform.tfvars.example .
}

check_trivyignore_policy() {
  local today max
  today="$(date -u +%F)"
  max="$(date_plus_days "$TRIVYIGNORE_MAX_DAYS")"
  awk -v today="$today" -v max="$max" '
    function flush() {
      if (id != "") {
        n++
        if (!st) { print "entry " id ": missing a non-empty statement"; bad = 1 }
        if (expiry !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { print "entry " id ": expired_at must be YYYY-MM-DD"; bad = 1 }
        else if (expiry < today) { print "entry " id ": expired on " expiry " (review or remove it)"; bad = 1 }
        else if (expiry > max) { print "entry " id ": expired_at " expiry " is after " max " (at most ~7 months ahead)"; bad = 1 }
        else { print "entry " id ": ok until " expiry }
      }
      id = ""; st = 0; expiry = ""
    }
    /^[[:space:]]*-[[:space:]]+id:/ { flush(); id = $NF; next }
    /^[[:space:]]+statement:[[:space:]]*[^[:space:]]/ { st = 1 }
    /^[[:space:]]+expired_at:/ { expiry = $NF; gsub(/["\047]/, "", expiry) }
    END { flush(); printf "%d ignore entries checked\n", n; exit bad }
  ' .trivyignore.yaml
}

check_actionlint() {
  need actionlint shellcheck
  actionlint -shellcheck "$(command -v shellcheck)"
}

check_policy_workflows() {
  local f rc=0 out ctx
  local -a files=()
  shopt -s nullglob
  files=(.github/workflows/*.yml .github/workflows/*.yaml)
  ((${#files[@]} > 0)) || {
    echo "no workflows found"
    return 1
  }
  for f in "${files[@]}"; do
    out="$(awk -v file="$f" -v cloud="$([[ "$f" == */ci.yml ]] && echo 0 || echo 1)" '
      function err(m) { printf "%s:%d: %s\n", file, NR, m; bad = 1 }
      function close_login() {
        in_login = 0
        if (!(lc && lt && ls)) { printf "%s:%d: azure/login needs client-id, tenant-id and subscription-id from vars.* (OIDC only)\n", file, login_line; bad = 1 }
      }
      in_login && (/^      - / || /^  [A-Za-z0-9_-]+:[[:space:]]*$/ || /^[^[:space:]]/) { close_login() }
      /^permissions:/ { top_perm = 1; in_top_perm = 1; next }
      in_top_perm && /^  contents: read[[:space:]]*$/ { top_read = 1; next }
      in_top_perm && /^  [a-z-]+:/ { err("top-level permissions must be exactly contents: read (raise per job): " $0) }
      in_top_perm && /^[^[:space:]]/ { in_top_perm = 0 }
      /^concurrency:/ { concurrency = 1 }
      /^on:/ { in_on = 1; next }
      in_on && /^[^[:space:]]/ { in_on = 0 }
      in_on && /^  [a-z_]+:/ { ev = $1; sub(/:$/, "", ev); events[ev] = 1 }
      /^jobs:/ { in_jobs = 1; next }
      in_jobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); jobs[job] = 1; first_step[job] = ""; next }
      in_jobs && /^    timeout-minutes:/ { timeout[job] = 1 }
      in_jobs && /^    runs-on: ubuntu-24\.04[[:space:]]*$/ { runs[job] = 1 }
      in_jobs && /^    environment: lab[[:space:]]*$/ { envlab[job] = 1 }
      in_jobs && /^    if: / { guard[job] = $0 }
      in_jobs && /^      id-token: write/ { oidc[job] = 1 }
      in_jobs && /^      - / && first_step[job] == "" { first_step[job] = $0 }
      /^[[:space:]-]*uses:/ {
        ref = $0; sub(/^[[:space:]-]*uses:[[:space:]]*/, "", ref)
        if (ref ~ /^\.\//) next
        if (ref !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+@[0-9a-f]+[[:space:]]+#[[:space:]]+v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$/) {
          err("pin actions to a full commit SHA with a trailing # vX.Y.Z comment: " ref)
        } else {
          sha = ref; sub(/^[^@]*@/, "", sha); sub(/[[:space:]].*$/, "", sha)
          if (length(sha) != 40) err("the commit SHA must have 40 characters: " ref)
        }
        if (ref ~ /^actions\/checkout@/) checkouts++
        if (ref ~ /^azure\/login@/) { azlogin++; in_login = 1; login_line = NR; lc = 0; lt = 0; ls = 0 }
        next
      }
      in_login && /^[[:space:]]+client-id: [$][{][{] vars[.][A-Z0-9_]+ [}][}][[:space:]]*$/ { lc = 1 }
      in_login && /^[[:space:]]+tenant-id: [$][{][{] vars[.]AZURE_TENANT_ID [}][}][[:space:]]*$/ { lt = 1 }
      in_login && /^[[:space:]]+subscription-id: [$][{][{] vars[.]AZURE_SUBSCRIPTION_ID [}][}][[:space:]]*$/ { ls = 1 }
      /persist-credentials: false/ { persist++ }
      /creds:|client-secret:|secrets\.AZURE|ARM_CLIENT_SECRET|ARM_ACCESS_KEY/ { err("OIDC only: no client secrets, creds or storage keys") }
      /continue-on-error:[[:space:]]*true/ { err("continue-on-error: true is forbidden") }
      /\|\|[[:space:]]*(true|echo|:)([[:space:]]|$)/ { err("never swallow errors (|| true, || echo, || :)") }
      /aquasecurity\/(trivy-action|setup-trivy)/ { err("trivy-action/setup-trivy are forbidden; trivy comes from scripts/install-tools.sh") }
      /(^|[^A-Za-z])sed[[:space:]].*\.tf([^A-Za-z]|$)/ { err("never edit Terraform files with sed") }
      /^[[:space:]]+(- )?run: terraform .* plan( |$)/ { plans++; if ($0 ~ / -lock=false( |$)/) nolock++; if ($0 ~ / -refresh=false( |$)/) norefresh++ }
      # The logs, the job summary and the artifacts of a public repository are public: the lists that
      # name the people and the addresses of the operator come from secrets (masked), and the job
      # masks each element on its own because Terraform prints them one by one.
      /^[[:space:]]+(TF_VAR_cluster_admin_principal_ids|TF_VAR_app_deployer_principal_ids|TF_VAR_api_server_authorized_ip_ranges|APP_DEPLOYER_PRINCIPAL_IDS):/ {
        lists_env = 1
        if ($0 !~ /secrets\.LAB_/) err("the lists of people and addresses must come from secrets.LAB_* (a variable is printed in clear in the logs)")
      }
      /::add-mask::/ { masks = 1 }
      /^[^#]*terraform .*(apply|destroy).*-lock=false/ { err("apply and destroy must keep the state lock") }
      END {
        if (in_login) close_login()
        if (!top_perm || !top_read) { printf "%s: top-level permissions must be exactly contents: read\n", file; bad = 1 }
        if (!concurrency) { printf "%s: a top-level concurrency group is required\n", file; bad = 1 }
        for (j in jobs) {
          if (!timeout[j]) { printf "%s: job %s has no timeout-minutes\n", file, j; bad = 1 }
          if (!runs[j]) { printf "%s: job %s must use runs-on: ubuntu-24.04\n", file, j; bad = 1 }
          if (cloud) {
            if (first_step[j] !~ /^      - name: Check /) { printf "%s: job %s: the first step must be \"Check ...\" (validate vars.* before anything else)\n", file, j; bad = 1 }
            if (oidc[j] && !envlab[j] && guard[j] !~ /vars\.AZURE_PLAN_CLIENT_ID != \047\047/) { printf "%s: job %s requests id-token: write without environment: lab\n", file, j; bad = 1 }
            if (!envlab[j] && !(guard[j] ~ /vars\.AZURE_PLAN_CLIENT_ID != \047\047/ && guard[j] ~ /github\.event\.pull_request\.head\.repo\.full_name == github\.repository/)) {
              printf "%s: job %s: cloud jobs run in environment lab, or (plan only) behind the vars + same-repository guard\n", file, j; bad = 1
            }
          }
        }
        if (cloud) {
          for (e in events) if (e != "workflow_dispatch" && !(e == "pull_request" && file ~ /terraform-plan\.yml$/)) { printf "%s: cloud workflows are workflow_dispatch only (a PR plan is the only exception), found: %s\n", file, e; bad = 1 }
          if (!azlogin && file !~ /terraform-(plan|apply)\.yml$/) { printf "%s: cloud workflows log in with azure/login (OIDC)\n", file; bad = 1 }
        }
        if (file ~ /terraform-plan\.yml$/ && (!plans || nolock != plans)) { printf "%s: every terraform plan step runs with -lock=false (the plan identity can only read the state)\n", file; bad = 1 }
        if (file ~ /terraform-plan\.yml$/ && norefresh != plans) { printf "%s: every terraform plan step runs with -refresh=false (the plan identity reads no data plane)\n", file; bad = 1 }
        if (lists_env && !masks) { printf "%s: a workflow that takes the lists of people and addresses must mask each element (::add-mask::)\n", file; bad = 1 }
        if (checkouts != persist) { printf "%s: every actions/checkout needs persist-credentials: false\n", file; bad = 1 }
        exit bad
      }' "$f")" || {
      printf '%s\n' "$out"
      rc=1
    }
  done
  if grep -n 'id-token: write' .github/workflows/ci.yml; then
    echo "ci.yml must never request id-token: write (OIDC is for cloud workflows only)"
    rc=1
  fi
  for ctx in static test e2e; do
    grep -qE "^  ${ctx}:[[:space:]]*$" .github/workflows/ci.yml || {
      echo "ci.yml must keep the stable job id '$ctx' (required status check)"
      rc=1
    }
    grep -qF "\"context\": \"$ctx\"" .github/rulesets/main.json || {
      echo ".github/rulesets/main.json must require the status check '$ctx'"
      rc=1
    }
  done
  f=.github/workflows/terraform-destroy.yml
  if [[ -f "$f" ]]; then
    # shellcheck disable=SC2016 # a literal $CONFIRM of the workflow script
    grep -qE '^[[:space:]]+if \[\[ "\$CONFIRM" != "destroy tx02v2-lab" \]\]; then$' "$f" || {
      echo "$f: the first step must refuse anything but the typed confirmation 'destroy tx02v2-lab'"
      rc=1
    }
    grep -qE '^[[:space:]]+run: bash scripts/leftovers\.sh --subscription' "$f" || {
      echo "$f: the destroy must end with scripts/leftovers.sh --subscription <id>"
      rc=1
    }
    grep -qE 'bash scripts/destroy\.sh --subscription' "$f" || {
      echo "$f: the destroy must run scripts/destroy.sh (platform uninstall, terraform destroy, force-unlock)"
      rc=1
    }
    # The leftover check and the login before it run after a failed destroy too.
    awk '/^      - name: Leftover check/ { l = 1 } l && /^        if: always\(\)/ { ok = 1 } END { exit !ok }' "$f" || {
      echo "$f: the leftover check must have if: always()"
      rc=1
    }
  fi
  return "$rc"
}

check_shellcheck() {
  local -a files=()
  need shellcheck
  mapfile -t files < <(find scripts platform -type f -name '*.sh' | sort)
  printf 'shellcheck: %s\n' "${files[@]}"
  shellcheck --external-sources --severity=style "${files[@]}"
}

check_kubeconform() {
  local rendered="$HARNESS_WORK_DIR/platform-manifests.yaml" full="$HARNESS_WORK_DIR/platform-full-manifests.yaml" edge="$HARNESS_WORK_DIR/edge-acme.yaml"
  need kubeconform
  mkdir -p "$HARNESS_WORK_DIR/kubeconform-cache"
  render_platform >"$rendered"
  kubeconform -strict -summary -output text \
    -kubernetes-version "$K8S_SCHEMA_KUBERNETES_VERSION" \
    -cache "$HARNESS_WORK_DIR/kubeconform-cache" \
    -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$K8S_SCHEMA_REF/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/$CRD_SCHEMA_REF/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    "$rendered" || return $?
  render_platform_full >"$full"
  kubeconform -strict -summary -output text -ignore-missing-schemas \
    -kubernetes-version "$K8S_SCHEMA_KUBERNETES_VERSION" \
    -cache "$HARNESS_WORK_DIR/kubeconform-cache" \
    -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$K8S_SCHEMA_REF/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/$CRD_SCHEMA_REF/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    "$full" || return $?
  bash platform/render-edge-acme.sh lab.example.com you@example.com \
    /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc \
    tx02v2-lab-frontend >"$edge"
  kubeconform -strict -summary -output text -ignore-missing-schemas \
    -kubernetes-version "$K8S_SCHEMA_KUBERNETES_VERSION" \
    -cache "$HARNESS_WORK_DIR/kubeconform-cache" \
    -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$K8S_SCHEMA_REF/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/$CRD_SCHEMA_REF/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    "$edge"
}

check_edge_acme() {
  local file="$HARNESS_WORK_DIR/edge-acme.yaml" id dr_id target runtime
  need kubectl
  id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc
  bash platform/render-edge-acme.sh lab.example.com you@example.com "$id" tx02v2-lab-frontend >"$file" || return $?
  [[ "$(kubectl_local "$file" '{{.kind}}/{{.metadata.name}}{{"\n"}}')" == $'Gateway/dx02v2\nClusterIssuer/tx02v2-letsencrypt-prod\nCertificate/dx02v2-tls' ]] || {
    echo "the ACME bootstrap must render exactly the lab Gateway, ClusterIssuer and Certificate"
    return 1
  }
  for wanted in \
    'hostname: lab.example.com' \
    'alb.networking.azure.io/alb-id: /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/tx02v2-lab/providers/Microsoft.ServiceNetworking/trafficControllers/tx02v2-lab-agc' \
    'server: https://acme-v02.api.letsencrypt.org/directory' \
    'email: you@example.com' \
    'gatewayHTTPRoute:' \
    'serviceType: ClusterIP' \
    'secretName: dx02v2-tls'; do
    grep -qF "$wanted" "$file" || { echo "ACME bootstrap missing $wanted"; return 1; }
  done
  for bad in 'lab..example.com|you@example.com' 'lab.example.com|not-an-email'; do
    if bash platform/render-edge-acme.sh "${bad%%|*}" "${bad#*|}" "$id" tx02v2-lab-frontend >/dev/null 2>&1; then
      echo "the ACME renderer accepted invalid configuration: $bad"
      return 1
    fi
  done
  if bash platform/render-edge-acme.sh lab.example.com you@example.com "$id" another-frontend >/dev/null 2>&1; then
    echo "the ACME renderer accepted a frontend outside the lab"
    return 1
  fi
  dr_id="${id%tx02v2-lab-agc}tx02v2-lab-dr-agc"
  for target in primary secondary; do
    runtime=tx02v2-lab
    [[ "$target" != secondary ]] || runtime=tx02v2-lab-dr
    bash platform/render-edge-acme.sh lab.example.com you@example.com "${id%tx02v2-lab-agc}$runtime-agc" "$runtime-frontend" "$target" >"$file" || return 1
    grep -qF "alb.networking.azure.io/alb-id: ${id%tx02v2-lab-agc}$runtime-agc" "$file" || return 1
    grep -qF "value: $runtime-frontend" "$file" || return 1
  done
  for bad in \
    "$id|tx02v2-lab-frontend|secondary" \
    "$dr_id|tx02v2-lab-dr-frontend|primary" \
    "$dr_id|tx02v2-lab-frontend|secondary" \
    "$id|tx02v2-lab-dr-frontend|primary" \
    "${id%tx02v2-lab-agc}another-agc|another-frontend|primary" \
    "$id|tx02v2-lab-frontend|arbitrary"; do
    IFS='|' read -r invalid_id invalid_frontend invalid_target <<<"$bad"
    if bash platform/render-edge-acme.sh lab.example.com you@example.com "$invalid_id" "$invalid_frontend" "$invalid_target" >/dev/null 2>&1; then
      echo 'the ACME renderer accepted an unrelated runtime or a mixed regional pair'
      return 1
    fi
  done
}

# The platform layer of contract v3, parsed from the rendered manifests (kubectl, no cluster):
# exact objects, Pod Security labels, Role rules, RoleBinding subjects, ClusterSecretStore;
# plus the Helm values and the pins of platform/versions.env.
# shellcheck disable=SC2016 # Go templates of kubectl, not shell expansions
check_contract_platform() {
  local rc=0 rendered="$HARNESS_WORK_DIR/contract-platform.yaml" full_rendered="$HARNESS_WORK_DIR/contract-platform-full.yaml" got want id key
  need kubectl
  mkdir -p "$HARNESS_WORK_DIR"
  render_platform >"$rendered"
  got="$(kubectl_local "$rendered" '{{.apiVersion}} {{.kind}}/{{.metadata.name}}{{if .metadata.namespace}} ns={{.metadata.namespace}}{{end}}{{"\n"}}' | sort)"
  want="$(printf '%s\n' "external-secrets.io/v1 ClusterSecretStore/azure-key-vault" "rbac.authorization.k8s.io/v1 Role/dx02v2-deployer ns=dx02v2" \
    "rbac.authorization.k8s.io/v1 RoleBinding/dx02v2-deployers ns=dx02v2" "v1 Namespace/dx02v2" "v1 Namespace/observability" | sort)"
  [[ "$got" == "$want" ]] || {
    printf 'platform/manifests must render exactly these objects (docs/CONTRATO.md):\n%s\ngot:\n%s\n' "$want" "$got"
    rc=1
  }
  for key in dx02v2 observability; do
    got="$(kubectl_local "$rendered" "{{if and (eq .kind \"Namespace\") (eq .metadata.name \"$key\")}}{{range \$k, \$v := .metadata.labels}}{{\$k}}={{\$v}}{{\"\\n\"}}{{end}}{{end}}")"
    if [[ "$key" == dx02v2 ]]; then
      if ! grep -qFx 'pod-security.kubernetes.io/enforce=restricted' <<<"$got" ||
        ! grep -qFx 'pod-security.kubernetes.io/enforce-version=latest' <<<"$got" ||
        ! grep -qFx 'istio.io/dataplane-mode=ambient' <<<"$got" ||
        ! grep -qFx 'policy.lab/enforce=true' <<<"$got"; then
        printf 'namespace %s must carry Pod Security restricted, Istio ambient and Gatekeeper enforcement labels; got:\n%s\n' "$key" "$got"
        rc=1
      fi
    elif [[ "$got" != $'istio.io/dataplane-mode=ambient\npod-security.kubernetes.io/enforce=restricted\npod-security.kubernetes.io/enforce-version=latest' ]]; then
      # Ambient: the AuthorizationPolicies of the app trust the Collector by mesh identity, and STRICT
      # mTLS refuses its plaintext synthetic probes.
      printf 'namespace %s must carry exactly the Pod Security labels enforce=restricted, enforce-version=latest and istio.io/dataplane-mode=ambient; got:\n%s\n' "$key" "$got"
      rc=1
    fi
  done
  got="$(kubectl_local "$rendered" '{{if eq .kind "Role"}}{{range .rules}}{{$r := .}}{{range $r.apiGroups}}{{$g := .}}{{range $r.resources}}{{$g}}|{{.}}|{{range $r.verbs}}{{.}} {{end}}{{"\n"}}{{end}}{{end}}{{if or $r.resourceNames $r.nonResourceURLs}}restricted-rule{{"\n"}}{{end}}{{end}}{{end}}' |
    awk -F'|' 'NF == 3 { n = split($3, v, " "); s = ""; for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (v[j] < v[i]) { t = v[i]; v[i] = v[j]; v[j] = t }
      for (i = 1; i <= n; i++) s = s (i > 1 ? "," : "") v[i]; print $1 "|" $2 "|" s; next } { print }' | sort)"
  want="$(printf '%s\n' "${CONTRACT_ROLE_RULES[@]}" | sort)"
  [[ "$got" == "$want" ]] || {
    echo "Role dx02v2-deployer differs from contract v3 (lines: apiGroup|resource|verbs):"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed -n 's/^</  contract:/p; s/^>/  rendered:/p'
    rc=1
  }
  got="$(kubectl_local "$rendered" '{{if eq .kind "RoleBinding"}}roleRef {{.roleRef.apiGroup}} {{.roleRef.kind}} {{.roleRef.name}}{{"\n"}}{{range .subjects}}{{.kind}} {{.name}} {{.apiGroup}}{{"\n"}}{{end}}{{end}}')"
  want="roleRef rbac.authorization.k8s.io Role dx02v2-deployer"
  for id in "${RENDER_DEPLOYERS[@]}"; do
    want+=$'\n'"User $id rbac.authorization.k8s.io"
  done
  [[ "$got" == "$want" ]] || {
    printf 'RoleBinding dx02v2-deployers must bind Role dx02v2-deployer to one User per object ID, in order:\n%s\ngot:\n%s\n' "$want" "$got"
    rc=1
  }
  got="$(kubectl_local platform/local/manifests/argocd-project-dx02v2.yaml \
    '{{if eq .kind "AppProject"}}{{range .spec.namespaceResourceWhitelist}}{{.group}}|{{.kind}}{{"\n"}}{{end}}{{end}}')"
  for kind in 'networking.istio.io|DestinationRule' 'security.istio.io|AuthorizationPolicy'; do
    grep -qFx "$kind" <<<"$got" || {
      printf 'local AppProject dx02v2 must allow the full-profile resource %s; got:\n%s\n' "$kind" "$got"
      rc=1
    }
  done
  # Repeated object IDs (deploy/principal-id also in app_deployer_principal_ids) render once.
  got="$(bash platform/render-manifests.sh "$RENDER_VAULT_URI" "${RENDER_DEPLOYERS[0]},${RENDER_DEPLOYERS[1]},${RENDER_DEPLOYERS[0]}" | grep -c '^  - kind: User$')"
  ((got == ${#RENDER_DEPLOYERS[@]})) || {
    echo "render-manifests.sh must render each deployer object ID once (got $got subjects)"
    rc=1
  }
  got="$(kubectl_local "$rendered" '{{if eq .kind "ClusterSecretStore"}}{{range $k, $v := .spec.provider}}{{$k}} {{end}}| {{.spec.provider.azurekv.authType}} {{.spec.provider.azurekv.vaultUrl}} {{.spec.provider.azurekv.serviceAccountRef.namespace}}/{{.spec.provider.azurekv.serviceAccountRef.name}} |{{range .spec.conditions}}{{range .namespaces}} {{.}}{{end}}{{range .namespaceSelector}} selector{{end}}{{range .namespaceRegexes}} regex{{end}}{{end}}{{end}}')"
  [[ "$got" == "azurekv | WorkloadIdentity $RENDER_VAULT_URI external-secrets/external-secrets | dx02v2" ]] || {
    echo "ClusterSecretStore azure-key-vault must use provider azurekv, authType WorkloadIdentity, the contract vaultUrl,"
    echo "serviceAccountRef external-secrets/external-secrets and be usable only from namespace dx02v2; got: $got"
    rc=1
  }
  # The renderer refuses inputs that are not a Key Vault URI or an object ID.
  for key in "https://example.com/" "not-a-uri"; do
    if bash platform/render-manifests.sh "$key" "${RENDER_DEPLOYERS[0]}" >/dev/null 2>&1; then
      echo "render-manifests.sh accepted the Key Vault URI '$key'"
      rc=1
    fi
  done
  for key in "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD" "dx02v2-gha-deploy" ""; do
    if bash platform/render-manifests.sh "$RENDER_VAULT_URI" "$key" >/dev/null 2>&1; then
      echo "render-manifests.sh accepted the deployer object ID '$key'"
      rc=1
    fi
  done
  render_platform_full >"$full_rendered"
  for key in 'RespectIgnoreDifferences=true' '/spec/source/path' \
    '/spec/source/kustomize/images' '/spec/source/kustomize/patches'; do
    grep -qF "$key" "$full_rendered" || {
      echo "full platform parent Application must preserve the deployer's dynamic child source field '$key'"
      rc=1
    }
  done
  for key in \
    'argoproj.io/v1alpha1 AppProject/platform ns=argocd' \
    'argoproj.io/v1alpha1 Application/platform ns=argocd' \
    'rbac.authorization.k8s.io/v1 Role/dx02v2-gitops-sync ns=argocd' \
    'rbac.authorization.k8s.io/v1 RoleBinding/dx02v2-gitops-sync ns=argocd' \
    'telemetry.istio.io/v1 Telemetry/mesh-default ns=istio-system'; do
    grep -qF "$key" <(kubectl_local "$full_rendered" '{{.apiVersion}} {{.kind}}/{{.metadata.name}}{{if .metadata.namespace}} ns={{.metadata.namespace}}{{end}}{{"\n"}}') || {
      echo "full platform renderer is missing $key"
      rc=1
    }
  done
  got="$(kubectl_local "$full_rendered" '{{if eq .metadata.name "dx02v2-gitops-sync"}}{{range .rules}}{{printf "%v|%v|%v|%v\n" .apiGroups .resources .resourceNames .verbs}}{{end}}{{end}}')"
  want='[argoproj.io]|[applications]|[dx02v2]|[get watch patch]'
  [[ "$got" == "$want" ]] || {
    printf 'GitOps deploy role must only get/watch/patch the dx02v2 Application; expected:\n%s\ngot:\n%s\n' "$want" "$got"
    rc=1
  }
  if ! grep -qF 'https://github.com/maringelix/tx02v2.git' "$full_rendered" ||
    ! grep -qF 'https://github.com/maringelix/dx02v2.git' "$full_rendered" ||
    ! grep -qF 'dxRevision: gitops/azure' "$full_rendered" ||
    grep -qE '__[A-Z][A-Z0-9_]*__' "$full_rendered"; then
    echo "full GitOps manifests must target the two forks, dx02v2's deploy revision and contain no placeholders"
    rc=1
  fi
  # Helm values (rendered by helm-template) and pins.
  grep -qE '^  namespace: azure-alb-system$' platform/values/alb-controller.yaml || {
    echo "ALB Controller: albController.namespace must be azure-alb-system (federated credential subject of tx02v2-lab-alb)"
    rc=1
  }
  grep -qE '^  installGatewayApiCRDs: true$' platform/values/alb-controller.yaml || {
    echo "ALB Controller: installGatewayApiCRDs must be true (dx02v2 uses Gateway API)"
    rc=1
  }
  grep -qE '^  securityPolicyFeatureFlag: true$' platform/values/alb-controller.yaml || {
    echo "ALB Controller: securityPolicyFeatureFlag must be true (WebApplicationFirewallPolicy of dx02v2)"
    rc=1
  }
  if grep -vE '^[[:space:]]*#' platform/values/alb-controller.yaml | grep -qE 'clientID|podIdentity'; then
    echo "ALB Controller: the client ID comes from install.sh (--set-string), never from the values file"
    rc=1
  fi
  grep -qE '^  name: external-secrets$' platform/values/external-secrets.yaml || {
    echo "ESO: the service account must be external-secrets (federated credential subject of tx02v2-lab-eso)"
    rc=1
  }
  grep -qE '^  azure\.workload\.identity/use: "true"$' platform/values/external-secrets.yaml || {
    echo "ESO: the controller pods must carry the label azure.workload.identity/use: \"true\" (contract)"
    rc=1
  }
  grep -qE '^  name: opentelemetry-collector$' platform/values/otel-collector.yaml || {
    echo "OpenTelemetry Collector: the service account must be opentelemetry-collector (federated credential subject of tx02v2-lab-otel)"
    rc=1
  }
  grep -qE '^  azure\.workload\.identity/use: "true"$' platform/values/otel-collector.yaml || {
    echo "OpenTelemetry Collector: the pods must carry the label azure.workload.identity/use: \"true\" (contract v3)"
    rc=1
  }
  if grep -vE '^[[:space:]]*#' platform/values/otel-collector.yaml | grep -qE 'client-id|InstrumentationKey='; then
    echo "OpenTelemetry Collector: the client ID and the connection string come from install.sh, never from the values file"
    rc=1
  fi
  platform_versions
  for key in ALB_CONTROLLER_CHART_SHA256 ALB_CONTROLLER_IMAGE_SHA256 ALB_CONTROLLER_IMAGE_AMD64_SHA256 \
    ALB_CONTROLLER_BOOTSTRAP_IMAGE_SHA256 ALB_CONTROLLER_BOOTSTRAP_IMAGE_AMD64_SHA256 \
    ALB_CONTROLLER_CRDS_IMAGE_SHA256 ALB_CONTROLLER_CRDS_IMAGE_AMD64_SHA256 OTEL_COLLECTOR_CHART_SHA256; do
    [[ "${PV[$key]:-}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "platform/versions.env: $key must be a SHA256 (64 hex characters)"
      rc=1
    }
  done
  for key in ESO_CHART_VERSION OTEL_COLLECTOR_CHART_VERSION; do
    [[ "${PV[$key]:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
      echo "platform/versions.env: $key is missing or malformed"
      rc=1
    }
  done
  return "$rc"
}

# Full profile admission binds the Azure workload identity to the same fork-specific deploy workflow
# that signs the promotion statement; the AGC CIDR remains the only plaintext edge exception.
check_image_admission_policy() {
  local rc=0 file=platform/manifests/full/image-verification.yaml rendered="$HARNESS_WORK_DIR/image-verification.yaml"
  bash scripts/tests/image-admission.sh || return 1
  for expected in \
    'kind: ImageValidatingPolicy' \
    '    mode: Kubernetes' \
    'failurePolicy: Fail' \
    'validationActions:' \
    '    - Deny' \
    '*.azurecr.io/dx02v2/api@sha256:*' \
    '*.azurecr.io/dx02v2/web@sha256:*' \
    '      - azure' \
    'deploy-azure.yml@refs/heads/main' \
    'https://token.actions.githubusercontent.com' \
    'https://github.com/maringelix/tx00v2/attestations/promoted-image/v1'; do
    grep -qF "$expected" "$file" || {
      echo "$file: missing fail-closed Azure promotion verification contract '$expected'"
      rc=1
    }
  done
  render_platform_full >"$rendered" || return 1
  grep -qF 'https://github.com/maringelix/dx02v2/.github/workflows/deploy-azure.yml@refs/heads/main' "$rendered" || {
    echo "render-manifests.sh did not bind the admission policy to the fork owner"
    rc=1
  }
  if grep -qE '__[A-Z][A-Z0-9_]*__' "$rendered"; then
    echo "the rendered full manifest still contains a template placeholder"
    rc=1
  fi
  if ! grep -qF 'ipBlocks:' "$rendered" || ! grep -qF "$RENDER_AGC_SUBNET_CIDR" "$rendered"; then
    echo "the rendered app security policy must restrict its edge exception to the contract AGC subnet"
    rc=1
  fi
  # portLevelMtls is valid only with a workload selector: the CRD refuses it on a namespace-wide
  # PeerAuthentication, which the JSON schema of kubeconform cannot see.
  got="$(kubectl_local "$rendered" '{{if eq .kind "PeerAuthentication"}}{{.metadata.name}}|{{if .spec.portLevelMtls}}ports{{end}}|{{if .spec.selector}}selector{{end}}{{"\n"}}{{end}}')" || return 1
  if grep -qE '\|ports\|$' <<<"$got"; then
    printf 'a PeerAuthentication with portLevelMtls needs a workload selector (the CRD refuses it otherwise):\n%s\n' "$(grep -E '\|ports\|$' <<<"$got")"
    rc=1
  fi
  grep -qxF 'default||' <<<"$got" || {
    echo "the namespace-wide PeerAuthentication default (STRICT, no selector, no port exception) is missing"
    rc=1
  }
  return "$rc"
}

# Admission must be installed before Argo CD can start the application, and cloud-full upgrades must
# create its waypoint, app policies, observability and Gatekeeper constraints before GitOps syncs.
check_full_install_order() {
  local body line last=0 n rc=0
  local -a expected=(
    'apply_full full/namespaces.yaml'
    'install_istio'
    'install_waypoint'
    'apply_full full/app-security.yaml'
    'install_observability'
    'apply_full full/app-monitoring.yaml'
    'install_policies'
    'install_image_admission'
    'install_gitops'
    'install_chart trivy-operator'
    'install_backup'
    'install_chart chaos-mesh'
  )
  body="$(sed -n '/^install_full() {/,/^}/p' platform/install.sh)"
  for line in "${expected[@]}"; do
    n="$(grep -nF "$line" <<<"$body" | head -n 1 | cut -d: -f1)"
    if [[ -z "$n" || "$n" -le "$last" ]]; then
      echo "platform/install.sh: expected full-profile step '$line' after line $last"
      rc=1
    else
      last=$n
    fi
  done
  grep -qF 'delete_all imagevalidatingpolicies.policies.kyverno.io' platform/uninstall.sh || {
    echo "platform/uninstall.sh must remove the fail-closed image policy before uninstalling Kyverno"
    rc=1
  }
  grep -qF 'remove_full_application_resources' platform/uninstall.sh || {
    echo "platform/uninstall.sh must remove the full-profile app policies and monitoring resources before uninstalling their CRDs"
    rc=1
  }
  grep -qF 'delete_full_persistent_volume_claims' platform/uninstall.sh || {
    echo "platform/uninstall.sh must remove observability PVCs before terraform destroy"
    rc=1
  }
  return "$rc"
}

# The contract keys the lab writes to App Configuration (terraform/envs/lab/contract.tf) are
# exactly the 17 keys of contract v4 (CONTRACT_KEYS, the list dx02v2 reads).
check_contract_appconfig() {
  local rc=0 got want key
  got="$(awk '/^  contract_keys = \{/ { inside = 1; next } inside && /^  \}/ { inside = 0 } inside && /^    "[^"]+"[[:space:]]*=/ { k = $1; gsub(/"/, "", k); print k }' terraform/envs/lab/contract.tf | sort)"
  want="$(printf '%s\n' "${CONTRACT_KEYS[@]}" | sort)"
  if [[ "$got" == "$want" ]]; then
    echo "terraform/envs/lab/contract.tf: the ${#CONTRACT_KEYS[@]} contract keys"
  else
    echo "terraform/envs/lab/contract.tf must define exactly the ${#CONTRACT_KEYS[@]} keys of contract v4:"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed -n 's/^</  missing:/p; s/^>/  unexpected:/p'
    rc=1
  fi
  grep -qE '^    "eso/cluster-secret-store"[[:space:]]*=[[:space:]]*"azure-key-vault"$' terraform/envs/lab/contract.tf || {
    echo "contract key eso/cluster-secret-store must be the literal azure-key-vault"
    rc=1
  }
  if ! grep -qE '^  key_prefix[[:space:]]*=[[:space:]]*"\$\{local\.project\}/\$\{local\.environment\}/"$' terraform/envs/lab/main.tf ||
    ! grep -qE '^  project[[:space:]]*=[[:space:]]*"tx02v2"$' terraform/envs/lab/main.tf ||
    ! grep -qE '^  environment[[:space:]]*=[[:space:]]*"lab"$' terraform/envs/lab/main.tf; then
    echo "terraform/envs/lab/main.tf: the App Configuration prefix must be tx02v2/lab/ (contract)"
    rc=1
  fi
  if [[ -f docs/CONTRATO.md ]]; then
    for key in "${CONTRACT_KEYS[@]}"; do
      grep -qE "^\| \`$key\` \|" docs/CONTRATO.md || {
        echo "docs/CONTRATO.md: contract key \`$key\` is not in the App Configuration table"
        rc=1
      }
    done
  else
    echo "docs/CONTRATO.md is missing (repo-structure fails): checked contract.tf only"
  fi
  return "$rc"
}

# Pulls the pinned charts (no cluster needed) and renders them with platform/values/*.yaml:
# the ALB Controller chart archive must match its recorded SHA256 (its images cannot be pinned by
# digest), then the values must be consumed as intended.
check_helm_template() {
  local rc=0 alb eso otel charts tgz want e
  need helm
  platform_versions
  export HELM_CACHE_HOME="$HARNESS_WORK_DIR/helm/cache" HELM_CONFIG_HOME="$HARNESS_WORK_DIR/helm/config" HELM_DATA_HOME="$HARNESS_WORK_DIR/helm/data"
  charts="$HARNESS_WORK_DIR/charts"
  rm -rf "$charts"
  mkdir -p "$charts"
  helm pull "$ALB_CHART_OCI" --version "${PV[ALB_CONTROLLER_CHART_VERSION]}" --destination "$charts"
  tgz="$charts/alb-controller-${PV[ALB_CONTROLLER_CHART_VERSION]}.tgz"
  [[ -f "$tgz" ]] || {
    echo "helm pull did not produce $tgz"
    return 1
  }
  [[ "$(sha256_of "$tgz")" == "${PV[ALB_CONTROLLER_CHART_SHA256]}" ]] || {
    echo "the ALB Controller chart ${PV[ALB_CONTROLLER_CHART_VERSION]} has SHA256 $(sha256_of "$tgz"), platform/versions.env records ${PV[ALB_CONTROLLER_CHART_SHA256]}"
    return 1
  }
  alb="$(helm template alb-controller "$tgz" --namespace azure-alb-system \
    --values platform/values/alb-controller.yaml \
    --set-string albController.podIdentity.clientID=00000000-0000-0000-0000-000000000000)"
  want="${PV[ALB_CONTROLLER_CHART_VERSION]}"
  local -a expect=(
    "image: \"mcr.microsoft.com/application-lb/images/alb-controller:$want\""
    "image:  \"mcr.microsoft.com/application-lb/images/alb-controller-bootstrap:$want\""
    "image: \"mcr.microsoft.com/application-lb/images/alb-controller-crds:$want\""
    "serviceAccountName: alb-controller-sa"
    "azure.workload.identity/client-id: 00000000-0000-0000-0000-000000000000"
    "azure.workload.identity/use: \"true\""
    "\"--namespace\", \"azure-alb-system\","
    "\"--alb-security-policy-feature-flag=true\","
    "- /alb-controller-crds/gateway-api-crds"
    "- /alb-controller-crds/extra-crds/alb.networking.azure.io_webapplicationfirewallpolicy.yaml"
    "replicas: 2"
    "kind: PodDisruptionBudget"
  )
  for e in "${expect[@]}"; do
    grep -qF -- "$e" <<<"$alb" || {
      echo "alb-controller chart: missing '$e'"
      rc=1
    }
  done
  if grep -qE '^kind: Namespace$' <<<"$alb"; then
    echo "alb-controller chart: the release must be installed in azure-alb-system (the chart then renders no Namespace)"
    rc=1
  fi
  eso="$(helm template external-secrets external-secrets \
    --repo "$ESO_CHART_REPO" --version "${PV[ESO_CHART_VERSION]}" --namespace external-secrets \
    --values platform/values/external-secrets.yaml \
    --set-string 'serviceAccount.annotations.azure\.workload\.identity/client-id=00000000-0000-0000-0000-000000000000' \
    --set-string 'serviceAccount.annotations.azure\.workload\.identity/tenant-id=00000000-0000-0000-0000-000000000000')"
  want="$(sed -n 's/^  tag: //p' platform/values/external-secrets.yaml)"
  (($(grep -cF "image: ghcr.io/external-secrets/external-secrets:$want" <<<"$eso") == 3)) || {
    echo "external-secrets chart: the controller, webhook and cert controller must all use the pinned digest"
    rc=1
  }
  grep -qE '^      serviceAccountName: external-secrets$' <<<"$eso" || {
    echo "external-secrets chart: the controller must run as the service account external-secrets"
    rc=1
  }
  if ! grep -qE '^    azure\.workload\.identity/client-id: "?00000000-0000-0000-0000-000000000000"?$' <<<"$eso" ||
    ! grep -qE '^    azure\.workload\.identity/tenant-id: "?00000000-0000-0000-0000-000000000000"?$' <<<"$eso"; then
    echo "external-secrets chart: the service account must carry the Workload ID client-id and tenant-id annotations"
    rc=1
  fi
  grep -qE '^        azure\.workload\.identity/use: "true"$' <<<"$eso" || {
    echo "external-secrets chart: the controller pods must carry azure.workload.identity/use: \"true\""
    rc=1
  }
  helm pull opentelemetry-collector --repo https://open-telemetry.github.io/opentelemetry-helm-charts \
    --version "${PV[OTEL_COLLECTOR_CHART_VERSION]}" --destination "$charts"
  tgz="$charts/opentelemetry-collector-${PV[OTEL_COLLECTOR_CHART_VERSION]}.tgz"
  [[ -f "$tgz" && "$(sha256_of "$tgz")" == "${PV[OTEL_COLLECTOR_CHART_SHA256]}" ]] || {
    echo "the opentelemetry-collector chart ${PV[OTEL_COLLECTOR_CHART_VERSION]} is missing or its SHA256 differs from platform/versions.env"
    return 1
  }
  otel="$(helm template opentelemetry-collector "$tgz" --namespace observability \
    --values platform/values/otel-collector.yaml \
    --set-string 'serviceAccount.annotations.azure\.workload\.identity/client-id=00000000-0000-0000-0000-000000000000')"
  want="$(sed -n 's/^  digest: //p' platform/values/otel-collector.yaml)"
  local -a expect_otel=(
    "image: \"otel/opentelemetry-collector-contrib@$want\""
    "serviceAccountName: opentelemetry-collector"
    "azure.workload.identity/client-id: \"00000000-0000-0000-0000-000000000000\""
    "azure.workload.identity/use: \"true\""
    "name: otel-collector-azure-monitor"
    "authenticator: azure_auth"
    "- https://monitor.azure.com/.default"
    "- azure_monitor"
  )
  for e in "${expect_otel[@]}"; do
    grep -qF -- "$e" <<<"$otel" || {
      echo "opentelemetry-collector chart: missing '$e'"
      rc=1
    }
  done
  [[ "$want" == "$(sed -n 's/^  digest: //p' platform/local/values/otel-collector.yaml)" ]] || {
    echo "the cloud and the local OpenTelemetry Collector must run the same image digest"
    rc=1
  }
  echo "rendered alb-controller ${PV[ALB_CONTROLLER_CHART_VERSION]} (chart SHA256 verified, $(wc -l <<<"$alb") lines), external-secrets ${PV[ESO_CHART_VERSION]} ($(wc -l <<<"$eso") lines) and opentelemetry-collector ${PV[OTEL_COLLECTOR_CHART_VERSION]} (chart SHA256 verified, $(wc -l <<<"$otel") lines)"
  return "$rc"
}

# Render every pinned chart in the cloud profile from its real archive, with Azure install-time
# placeholders. This catches values that do not match the chart schema and enforces digest-pinned
# images and ClusterIP services before the expensive CI stages run.
check_helm_template_full() {
  local rc=0 entry repo_key version_key sha_key chart release ns value_list tgz f content values_file rendered images bad svc count=0 sizing sizing_cpu sizing_memory docs_cpu docs_memory
  local test_storage_uri="https://tx02v2labb602d594velero.blob.core.windows.net"
  local test_client_id="00000000-0000-0000-0000-000000000000"
  local -a files=() args=() entries=()
  need helm
  load_local_versions
  export HELM_CACHE_HOME="$HARNESS_WORK_DIR/helm/cache" HELM_CONFIG_HOME="$HARNESS_WORK_DIR/helm/config" HELM_DATA_HOME="$HARNESS_WORK_DIR/helm/data"
  local out="$HARNESS_WORK_DIR/full-charts"
  rm -rf "$out"
  mkdir -p "$out/values"
  mapfile -t entries < <(chart_table)
  for entry in "${entries[@]}"; do
    read -r repo_key version_key sha_key chart release ns value_list <<<"$entry"
    [[ -n "${LV[$repo_key]:-}" && -n "${LV[$version_key]:-}" && -n "${LV[$sha_key]:-}" ]] || {
      echo "platform/full/charts.txt: missing pin variable for $chart ($repo_key/$version_key/$sha_key)"
      rc=1
      continue
    }
    IFS=, read -ra files <<<"$value_list"
    args=()
    for f in "${files[@]}"; do
      [[ -f "platform/$f" ]] || {
        echo "platform/full/charts.txt: missing values file platform/$f"
        rc=1
        continue 2
      }
      content="$(<"platform/$f")"
      content="${content//__VELERO_CLIENT_ID__/00000000-0000-0000-0000-000000000000}"
      content="${content//__TRIVY_CLIENT_ID__/$test_client_id}"
      content="${content//__KYVERNO_CLIENT_ID__/$test_client_id}"
      content="${content//__OTEL_CLIENT_ID__/$test_client_id}"
      content="${content//__VELERO_STORAGE_ACCOUNT_URI__/$test_storage_uri}"
      content="${content//__S3_BUCKET__/tx02v2-lab-velero}"
      content="${content//__S3_ENDPOINT__/$test_storage_uri}"
      content="${content//__AZURE_SUBSCRIPTION_ID__/00000000-0000-0000-0000-000000000000}"
      content="${content//__AKS_NODE_RESOURCE_GROUP__/MC_tx02v2-lab_tx02v2-lab_eastus2}"
      values_file="$out/values/$chart-$((${#args[@]} / 2)).yaml"
      printf '%s\n' "$content" >"$values_file"
      args+=(--values "$values_file")
    done
    tgz="$(pull_chart "$out/archives" "${LV[$repo_key]}" "$chart" "${LV[$version_key]}" "${LV[$sha_key]}")"
    rendered="$out/$chart.yaml"
    helm template "$release" "$tgz" --namespace "$ns" --kube-version "$K8S_SCHEMA_KUBERNETES_VERSION" \
      "${args[@]}" >"$rendered" || {
      echo "$chart ${LV[$version_key]}: helm template failed"
      rc=1
      continue
    }
    images="$(awk '
      function indent(line, spaces) {
        spaces = line
        sub(/[^ ].*$/, "", spaces)
        return length(spaces)
      }
      {
        if (in_block) {
          if ($0 ~ /^[[:space:]]*$/ || indent($0) > block_indent) next
          in_block = 0
        }
        if ($0 ~ /:[[:space:]]*[|>][-+0-9]*[[:space:]]*$/) {
          block_indent = indent($0)
          in_block = 1
          next
        }
        if ($0 ~ /^[[:space:]-]*image:[[:space:]]*/) {
          value = $0
          sub(/^[[:space:]-]*image:[[:space:]]*/, "", value)
          sub(/^["\047]/, "", value)
          sub(/["\047].*$/, "", value)
          print value
        }
      }
    ' "$rendered" | sort -u)" || images=""
    bad=""
    [[ -z "$images" ]] || bad="$(grep -vE '@sha256:[0-9a-f]{64}$' <<<"$images")" || bad=""
    if [[ -n "$bad" ]]; then
      printf '%s: images not pinned by digest:\n%s\n' "$chart" "$bad"
      rc=1
    fi
    svc="$(awk '/^kind: Service$/ { s = 1 } s && /^  type: (LoadBalancer|NodePort)/ { print; s = 0 } /^---/ { s = 0 }' "$rendered")"
    if [[ -n "$svc" ]]; then
      printf '%s: Services must stay ClusterIP:\n%s\n' "$chart" "$svc"
      rc=1
    fi
    if grep -qE '__[A-Z][A-Z0-9_]*__' "$rendered"; then
      echo "$chart: unresolved placeholder in the rendered chart"
      rc=1
    fi
    if [[ "$chart" == trivy-operator ]]; then
      for expected in 'azure.workload.identity/client-id: 00000000-0000-0000-0000-000000000000' \
        'scanJob.podTemplateLabels: "azure.workload.identity/use=true"'; do
        grep -qF "$expected" "$rendered" || {
          echo "trivy-operator: private ACR scans need the Azure Workload ID service account and scan-job label ($expected)"
          rc=1
        }
      done
    fi
    if [[ "$chart" == kyverno ]]; then
      for expected in 'azure.workload.identity/client-id: 00000000-0000-0000-0000-000000000000' \
        'azure.workload.identity/use: "true"'; do
        grep -qF "$expected" "$rendered" || {
          echo "kyverno: image admission needs the Azure Workload ID service account and pod label ($expected)"
          rc=1
        }
      done
    fi
    if [[ "$chart" == opentelemetry-collector ]]; then
      for expected in 'azure.workload.identity/client-id: "00000000-0000-0000-0000-000000000000"' \
        'azure.workload.identity/use: "true"' 'serviceAccountName: opentelemetry-collector'; do
        grep -qF "$expected" "$rendered" || {
          echo "opentelemetry-collector: full upgrade must retain its Azure Workload ID ($expected)"
          rc=1
        }
      done
    fi
    count=$((count + 1))
    echo "$chart ${LV[$version_key]}: $(grep -c '^kind:' "$rendered" || :) objects"
  done
  [[ "$count" == 16 ]] || {
    echo "platform/full/charts.txt rendered $count charts; expected 16"
    rc=1
  }
  sizing="$(scripts/platform-sizing.sh 2 "$out")"
  sizing_cpu="$(sed -n 's/^cpu_millicores=//p' <<<"$sizing")"
  sizing_memory="$(sed -n 's/^memory_mib=//p' <<<"$sizing")"
  docs_cpu="$(sed -nE 's#^[|][[:space:]]*full[[:space:]]*[|][[:space:]]*([0-9]+) mCPU / [0-9]+ MiB[[:space:]]*[|].*#\1#p' docs/CUSTOS.md)"
  docs_memory="$(sed -nE 's#^[|][[:space:]]*full[[:space:]]*[|][[:space:]]*[0-9]+ mCPU / ([0-9]+) MiB[[:space:]]*[|].*#\1#p' docs/CUSTOS.md)"
  if [[ -z "$docs_cpu" || -z "$docs_memory" ]]; then
    echo "docs/CUSTOS.md: missing the full-profile requests row"
    rc=1
  elif [[ "$sizing_cpu" != "$docs_cpu" || "$sizing_memory" != "$docs_memory" ]]; then
    printf 'R4.7 sizing differs: rendered %s mCPU / %s MiB; docs/CUSTOS.md says %s mCPU / %s MiB\n' \
      "$sizing_cpu" "$sizing_memory" "$docs_cpu" "$docs_memory"
    rc=1
  fi
  helm template platform platform/gitops --namespace argocd \
    --set-string dxRepoURL=https://github.com/maringelix/dx02v2.git \
    --set-string dxRevision=gitops/azure --set-string dxPath=deploy/k8s/overlays/azure \
    --set-string appNamespace=dx02v2 >"$out/platform-gitops.yaml" || {
    echo "platform/gitops: helm template failed"
    rc=1
  }
  if grep -qE '__[A-Z][A-Z0-9_]*__' "$out/platform-gitops.yaml"; then
    echo "platform/gitops: unresolved placeholder in the rendered chart"
    rc=1
  fi
  for key in 'kind: Gateway' 'kind: HTTPRoute' 'kind: HealthCheckPolicy' 'kind: WebApplicationFirewallPolicy' \
    'group: networking.istio.io' 'kind: DestinationRule' 'group: security.istio.io' 'kind: AuthorizationPolicy'; do
    grep -qF "$key" "$out/platform-gitops.yaml" || {
      echo "platform/gitops AppProject must allow the app's Azure resource '$key'"
      rc=1
    }
  done
  return "$rc"
}

# Keep the estimator itself covered with a tiny synthetic render; the chart check also feeds it every
# real cloud-profile chart render above.
check_platform_sizing() {
  local out="$HARNESS_WORK_DIR/sizing-fixture"
  mkdir -p "$out"
  cat >"$out/workloads.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: api
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
---
apiVersion: apps/v1
kind: DaemonSet
spec:
  template:
    spec:
      containers:
        - name: agent
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
---
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
spec:
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
EOF
  local got want
  got="$(scripts/platform-sizing.sh 2 "$out")"
  want=$'cpu_millicores=550\nmemory_mib=1152\nnodes=2'
  [[ "$got" == "$want" ]] || {
    printf 'platform-sizing: expected:\n%s\ngot:\n%s\n' "$want" "$got"
    return 1
  }
}

check_fork_references() {
  local rc=0 entry repo_key version_key sha_key chart release ns value_list f
  local -a entries=() files=()
  mapfile -t entries < <(chart_table)
  [[ "${#entries[@]}" == 16 ]] || {
    echo "platform/full/charts.txt must list exactly 16 pinned charts"
    rc=1
  }
  for entry in "${entries[@]}"; do
    read -r repo_key version_key sha_key chart release ns value_list <<<"$entry"
    IFS=, read -ra files <<<"$value_list"
    for f in "${files[@]}"; do
      [[ -f "platform/$f" ]] || { echo "chart $chart references missing values platform/$f"; rc=1; }
    done
  done
  if grep -RniE 'tx01v2|dx01v2|maringelix/(tx|dx)02v2' \
    platform/full platform/gitops platform/manifests/full platform/values/full; then
    echo "the cloud profile must use tx02v2/dx02v2 templates and contain no account-specific fork URL"
    rc=1
  fi
  grep -qE '^dxRepoURL: https://github.com/example-owner/dx02v2\.git$' platform/gitops/values.yaml || {
    echo "platform/gitops values must retain the fork-owner placeholder"
    rc=1
  }
  grep -qE '^dxRevision: gitops/azure$' platform/gitops/values.yaml || {
    echo "platform/gitops values must use dx02v2's Azure deployment branch"
    rc=1
  }
  return "$rc"
}

check_gitleaks() {
  need gitleaks git
  if git rev-parse --verify -q HEAD >/dev/null; then
    echo "repository has commits: scanning the full history (gitleaks git)"
    gitleaks git --no-banner --redact --log-level warn .
  else
    echo "no commits yet: scanning the working tree (gitleaks dir)"
    gitleaks dir --no-banner --redact --log-level warn .
  fi
}

check_terraform_test() {
  need terraform
  tf_init "$1"
  terraform -chdir="$1" test -no-color
}

# --- Local lab (terraform/envs/local + platform/local) ---------------------------------------------

# load_local_versions -> LV[KEY]=VALUE from platform/versions.env and platform/local/versions.env.
declare -A LV=()
load_local_versions() {
  local f key value
  for f in platform/versions.env platform/local/versions.env; do
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[A-Z0-9_]+$ ]] && LV[$key]="$value"
    done < <(grep -E '^[A-Z0-9_]+=' "$f")
  done
}

check_local_versions() {
  local rc=0 key entry prefix version_key sha_key kind_minor aks_minor
  load_versions
  load_local_versions
  for key in "${!LV[@]}"; do
    if [[ "$key" == *_SHA256 && ! "${LV[$key]}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "platform/local/versions.env: $key must be a SHA256 (64 hex characters)"
      rc=1
    fi
  done
  for entry in "${LOCAL_CHARTS[@]}"; do
    read -r prefix version_key sha_key _ <<<"$entry"
    [[ "${LV[$prefix]:-}" =~ ^https:// ]] || {
      echo "platform/local/versions.env: $prefix must be an https URL"
      rc=1
    }
    [[ -n "${LV[$version_key]:-}" && -n "${LV[$sha_key]:-}" ]] || {
      echo "platform/local/versions.env: $version_key and $sha_key are required"
      rc=1
    }
  done
  [[ "${LV[GATEKEEPER_VERSION]:-}" == "$GATOR_VERSION" ]] || {
    echo "tools/versions.env GATOR_VERSION ($GATOR_VERSION) must equal GATEKEEPER_VERSION (${LV[GATEKEEPER_VERSION]:-?})"
    rc=1
  }
  kind_minor="$(grep -oE 'kindest/node:v[0-9]+\.[0-9]+' terraform/envs/local/kind-config.yaml | sed 's/.*:v//')"
  aks_minor="$(awk '/^variable "kubernetes_version"/ { a = 1 } a && /^[[:space:]]*default[[:space:]]*=/ { gsub(/[" ]/, ""); sub(/^default=/, ""); print; exit }' terraform/envs/lab/variables.tf)"
  [[ -n "$kind_minor" && "$kind_minor" == "$aks_minor" ]] || {
    echo "the kind node image (${kind_minor:-?}) must run the Kubernetes minor of the AKS lab (kubernetes_version = ${aks_minor:-?})"
    rc=1
  }
  grep -qE 'kindest/node:v[0-9.]+@sha256:[0-9a-f]{64}$' terraform/envs/local/kind-config.yaml || {
    echo "terraform/envs/local/kind-config.yaml must pin the node image by digest"
    rc=1
  }
  [[ "$(grep -c 'tag: v'"${LV[ESO_CHART_VERSION]}"'@sha256' platform/values/external-secrets.yaml)" == 3 ]] || {
    echo "the local platform reuses platform/values/external-secrets.yaml: it must pin ESO ${LV[ESO_CHART_VERSION]} by digest"
    rc=1
  }
  return "$rc"
}

# local_chart_values NAME -> --values arguments for one chart, with the install-time placeholders of
# platform/local/install.sh replaced by example values.
local_chart_values() {
  local list=$1 v out="$HARNESS_WORK_DIR/local-values" f
  local -a parts=()
  mkdir -p "$out"
  local i=0
  IFS=, read -ra parts <<<"$list"
  for v in "${parts[@]}"; do
    i=$((i + 1))
    f="platform/local/values/$v.yaml"
    sed -e 's|__S3_BUCKET__|tx02v2-local-velero|' -e 's|__S3_ENDPOINT__|http://10.251.0.12:7070|' \
      -e 's|__REGISTRY_ENDPOINT__|10.251.0.10:5000|' "$f" >"$out/$i-$(basename "$v").yaml"
    printf -- '--values\n%s\n' "$out/$i-$(basename "$v").yaml"
  done
}

# Pulls every chart of the local platform (SHA256-verified, like install.sh), renders it with its
# values and asserts: every image pinned by digest, no :latest, no Service of type LoadBalancer or
# NodePort (only the Istio gateways get a LoadBalancer, created at run time), no placeholder left.
# A chart with a size overlay (platform/local/values/small/<chart>.yaml, LOCAL_SIZE=small) is rendered
# twice: the same checks hold for both, and the overlay changes sizes, never images.
check_helm_template_local() {
  local rc=0 entry repo_key version_key sha_key chart values tgz rendered out images bad svc variant label f
  local default_images
  local -a args=() extra=() variants=() charts=()
  need helm
  load_local_versions
  export HELM_CACHE_HOME="$HARNESS_WORK_DIR/helm/cache" HELM_CONFIG_HOME="$HARNESS_WORK_DIR/helm/config" HELM_DATA_HOME="$HARNESS_WORK_DIR/helm/data"
  out="$HARNESS_WORK_DIR/local-charts"
  rm -rf "$out"
  mkdir -p "$out"
  for entry in "${LOCAL_CHARTS[@]}"; do
    read -r _ _ _ chart _ <<<"$entry"
    charts+=("$chart")
  done
  for f in platform/local/values/small/*.yaml; do
    [[ -e "$f" ]] || continue
    printf '%s\n' "${charts[@]}" | grep -qxF "$(basename "$f" .yaml)" || {
      echo "$f: no chart of that name in LOCAL_CHARTS (the size overlays are applied by chart name)"
      rc=1
    }
  done
  for entry in "${LOCAL_CHARTS[@]}"; do
    read -r repo_key version_key sha_key chart values <<<"$entry"
    mkdir -p "$out/$chart"
    helm pull "$chart" --repo "${LV[$repo_key]}" --version "${LV[$version_key]}" --destination "$out/$chart" >/dev/null
    tgz="$(find "$out/$chart" -maxdepth 1 -name '*.tgz' -print -quit)"
    [[ "$(sha256_of "$tgz")" == "${LV[$sha_key]:-}" ]] || {
      echo "$chart ${LV[$version_key]}: SHA256 $(sha256_of "$tgz") differs from $sha_key"
      rc=1
      continue
    }
    mapfile -t args < <(local_chart_values "$values")
    variants=(default)
    [[ -f "platform/local/values/small/$chart.yaml" ]] && variants+=(small)
    default_images=""
    for variant in "${variants[@]}"; do
      rendered="$out/$chart.yaml"
      label="$chart"
      extra=()
      if [[ "$variant" == small ]]; then
        rendered="$out/$chart-small.yaml"
        label="$chart (size small)"
        extra=(--values "platform/local/values/small/$chart.yaml")
      fi
      helm template "$chart" "$tgz" --namespace lab --kube-version "$K8S_SCHEMA_KUBERNETES_VERSION" "${args[@]}" "${extra[@]}" >"$rendered" || {
        echo "$label: helm template failed"
        rc=1
        continue
      }
      # Some charts (istio base) render no workload at all.
      # ConfigMaps are left out: istiod ships its injection templates (with template placeholders) in one.
      images="$(awk '/^---/ { flush(); next } { doc = doc $0 "\n" } /^kind: ConfigMap$/ { skip = 1 }
        function flush() { if (!skip) printf "%s", doc; doc = ""; skip = 0 } END { flush() }' "$rendered" |
        grep -hoE '^[[:space:]-]*image:[[:space:]]*["'\'']?[^"'\''[:space:]]+' | sed -E 's/^[[:space:]-]*image:[[:space:]]*["'\'']?//' | sort -u)" || images=""
      bad=""
      [[ -z "$images" ]] || bad="$(grep -vE '@sha256:[0-9a-f]{64}$' <<<"$images")" || bad=""
      if [[ -n "$bad" ]]; then
        printf '%s: images not pinned by digest:\n%s\n' "$label" "$bad"
        rc=1
      fi
      svc="$(awk '/^kind: Service$/ { s = 1 } s && /^  type: (LoadBalancer|NodePort)/ { print; s = 0 } /^---/ { s = 0 }' "$rendered")"
      if [[ -n "$svc" ]]; then
        printf '%s: Services must stay ClusterIP:\n%s\n' "$label" "$svc"
        rc=1
      fi
      if grep -qE '__[A-Z_]+__' "$rendered"; then
        echo "$label: unresolved placeholder in the rendered chart"
        rc=1
      fi
      if [[ "$variant" == default ]]; then
        default_images="$images"
      elif [[ "$images" != "$default_images" ]]; then
        echo "$label: the size overlay changes the images (it may only change sizes)"
        rc=1
      fi
      echo "$label ${LV[$version_key]}: $(grep -c . <<<"$images" || :) images, $(grep -c '^kind:' "$rendered" || :) objects"
    done
  done
  return "$rc"
}

# kubeconform on the plain manifests of the local platform (the Gatekeeper constraints are custom
# kinds created by their templates: gator verify covers them).
check_kubeconform_local() {
  need kubeconform
  mkdir -p "$HARNESS_WORK_DIR/kubeconform-cache"
  kubeconform -strict -summary -output text \
    -kubernetes-version "$K8S_SCHEMA_KUBERNETES_VERSION" \
    -cache "$HARNESS_WORK_DIR/kubeconform-cache" \
    -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$K8S_SCHEMA_REF/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/$CRD_SCHEMA_REF/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    platform/local/manifests platform/local/policies/templates platform/local/policies/tests/namespace-dx02v2.yaml
}

check_policy_gator() {
  need gator
  gator verify -v platform/local/policies/tests/
  gator verify -v platform/full/policies/tests/
}

check_local_lab_e2e() {
  need terraform kind kubectl helm docker curl git ssh
  docker info >/dev/null 2>&1 || skip "docker is installed but the daemon is not reachable"
  bash scripts/local-lab.sh e2e
}

register_checks() {
  local d
  register static tool-versions check_tool_versions
  register static repo-structure check_repo_structure
  register static version-consistency check_version_consistency
  register static policy-terraform check_policy_terraform
  register static policy-tags check_policy_tags
  register static policy-identifiers check_policy_identifiers
  register static volume-restore-wiring 'bash scripts/tests/volume-restore-wiring.sh'
  register static finops 'bash scripts/tests/finops.sh'
  register static finops-charts 'bash scripts/tests/finops-charts.sh'
  register static backup-credentials 'bash scripts/tests/backup-credentials.sh'
  register static dr-current-secrets 'bash scripts/tests/dr-secrets.sh'
  register static region-target 'bash scripts/tests/region-target.sh'
  register static cloud-install 'bash scripts/tests/cloud-install.sh'
  register static policy-workflows check_policy_workflows
  register static policy-scripts check_policy_scripts
  register static destroy-flow check_destroy_flow
  register static local-preflight check_local_preflight
  register static leftovers-flow check_leftovers_flow
  register static trivyignore-policy check_trivyignore_policy
  register static contract-platform check_contract_platform
  register static image-admission-policy check_image_admission_policy
  register static full-install-order check_full_install_order
  register static contract-appconfig check_contract_appconfig
  register static terraform-fmt check_terraform_fmt
  register static terraform-lockfiles check_terraform_lockfiles
  for d in terraform/bootstrap terraform/envs/lab terraform/envs/local "$REPO_ROOT"/terraform/modules/*/; do
    d="${d#"$REPO_ROOT"/}"
    d="${d%/}"
    register static "terraform-validate:${d#terraform/}" "check_terraform_validate $d"
  done
  register static tflint check_tflint
  register static trivy-config check_trivy_config
  register static trivy-config-tfvars check_trivy_config_tfvars
  register static actionlint check_actionlint
  register static shellcheck check_shellcheck
  register static kubeconform check_kubeconform
  register static edge-acme check_edge_acme
  register static helm-template check_helm_template
  register static helm-template-full check_helm_template_full
  register static platform-sizing check_platform_sizing
  register static fork-references check_fork_references
  register static local-versions check_local_versions
  register static helm-template-local check_helm_template_local
  register static kubeconform-local check_kubeconform_local
  register static policy-gator check_policy_gator
  register static gitleaks check_gitleaks
  register test tool-versions check_tool_versions
  register test terraform-test:bootstrap "check_terraform_test terraform/bootstrap"
  register test terraform-test:envs/lab "check_terraform_test terraform/envs/lab"
  register test terraform-test:envs/local "check_terraform_test terraform/envs/local"
  register e2e local-lab-e2e check_local_lab_e2e
}

# ---------------------------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -a FAILED=()

run_check() {
  local name=$1 cmd=$2 log rc start secs status reason="" lines
  local -a parts=()
  read -ra parts <<<"$cmd"
  log="$HARNESS_WORK_DIR/logs/${name//[^A-Za-z0-9._-]/_}.log"
  start=$SECONDS
  set +e
  (
    set -euo pipefail
    cd "$REPO_ROOT"
    "${parts[@]}"
  ) >"$log" 2>&1
  rc=$?
  set -e
  secs=$((SECONDS - start))
  case "$rc" in
    0) status=PASS ;;
    "$SKIP_CODE")
      reason="$(sed -n 's/^SKIP_REASON: //p' "$log" | tail -n 1)"
      if strict; then
        status=FAIL
        reason="$reason (SKIP is not allowed with HARNESS_STRICT=1)"
      else
        status=SKIP
      fi
      ;;
    *) status=FAIL ;;
  esac
  printf '%s %s (%ss)%s\n' "$status" "$name" "$secs" "${reason:+ - $reason}"
  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    FAIL)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILED+=("$name")
      ;;
  esac
  if [[ "$status" == FAIL || "$HARNESS_VERBOSE" == 1 ]]; then
    lines="$(wc -l <"$log")"
    if ((lines > 400)); then
      echo "    ... last 400 of $lines lines (full log: $log)"
    fi
    tail -n 400 "$log" | sed 's/^/    /'
  fi
}

list_checks() {
  local i
  echo "stages:"
  echo "  static  policies, contract, fmt, validate, lock files, tflint, trivy, actionlint, shellcheck, kubeconform, helm template, gitleaks"
  echo "  test    terraform test (mocked providers) for terraform/bootstrap, terraform/envs/lab and terraform/envs/local"
  echo "  e2e     local lab on Docker: terraform apply of envs/local, platform/local, every probe, destroy + leftovers"
  echo "  all     static + test + e2e"
  echo "checks:"
  for i in "${!CHECK_NAME[@]}"; do
    printf '  %-7s %s\n' "${CHECK_STAGE[$i]}" "${CHECK_NAME[$i]}"
  done
}

usage() {
  echo "usage: $0 <stage>...   (stages: static, test, e2e, all, list)" >&2
  exit 2
}

main() {
  local arg stage i start_all=$SECONDS
  local -a stages=()
  declare -A seen=()
  (($# > 0)) || usage
  register_checks
  for arg in "$@"; do
    case "$arg" in
      static | test | e2e) stages+=("$arg") ;;
      all) stages+=(static test e2e) ;;
      list)
        list_checks
        return 0
        ;;
      *) usage ;;
    esac
  done
  mkdir -p "$HARNESS_WORK_DIR/logs"
  echo "harness: stages=${stages[*]} strict=$HARNESS_STRICT work_dir=$HARNESS_WORK_DIR${HARNESS_ONLY:+ only=$HARNESS_ONLY}"
  for stage in "${stages[@]}"; do
    for i in "${!CHECK_NAME[@]}"; do
      [[ "${CHECK_STAGE[$i]}" == "$stage" && -z "${seen[${CHECK_NAME[$i]}]:-}" ]] || continue
      [[ -z "$HARNESS_ONLY" || "${CHECK_NAME[$i]}" =~ $HARNESS_ONLY ]] || continue
      seen[${CHECK_NAME[$i]}]=1
      run_check "${CHECK_NAME[$i]}" "${CHECK_CMD[$i]}"
    done
  done
  echo "summary: $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)) checks, $PASS_COUNT PASS, $FAIL_COUNT FAIL, $SKIP_COUNT SKIP ($((SECONDS - start_all))s, strict=$HARNESS_STRICT)"
  if ((PASS_COUNT + FAIL_COUNT + SKIP_COUNT == 0)); then
    echo "no check matched HARNESS_ONLY='$HARNESS_ONLY'"
    return 1
  fi
  if ((FAIL_COUNT > 0)); then
    echo "failed: ${FAILED[*]}"
    return 1
  fi
}

main "$@"
