#!/usr/bin/env bash
# Installs the platform layer on the lab cluster (never done by Terraform):
#   1. ALB Controller of Application Gateway for Containers (namespace azure-alb-system, GatewayClass
#      azure-alb-external), from the OCI chart whose SHA256 is recorded in platform/versions.env
#   2. External Secrets Operator (namespace external-secrets) with Microsoft Entra Workload ID
#   3. platform/manifests (namespaces dx02v2 and observability, deployer RBAC, ClusterSecretStore
#      azure-key-vault)
#   4. OpenTelemetry Collector (namespace observability, contract v2): OTLP from the app, traces to
#      the Application Insights tx02v2-lab-traces with the Workload ID of tx02v2-lab-otel
# CLOUD-MUTATING: run it only when you mean to (docs/RUNBOOK.md). Needs the Azure CLI (az login, or
# azure/login in the platform workflow), kubectl, helm and kubelogin (scripts/install-tools.sh
# kubectl helm kubelogin) and an identity listed in cluster_admin_principal_ids.
# Reads the contract keys from App Configuration, the client IDs of tx02v2-lab-alb, tx02v2-lab-eso
# and tx02v2-lab-otel and the connection string of tx02v2-lab-traces (an address: local
# authentication is off there); nothing comes from the Terraform state. Environment:
#   APPCONFIG_ENDPOINT          contract store (default: https://tx02v2-lab-<suffix>.azconfig.io of
#                               the active subscription)
#   APP_DEPLOYER_PRINCIPAL_IDS  JSON list of extra deployer object IDs (the Terraform variable
#                               app_deployer_principal_ids), default []
# Every Azure token is acquired in the first minutes (the GitHub OIDC assertion behind azure/login
# expires after 5-10 minutes; the Azure CLI then reuses the tokens it holds). Re-running it upgrades
# in place. It installs only on the contract cluster tx02v2-lab, and only when that cluster carries
# the tag Project=tx02v2; the kubeconfig is a temporary file (~/.kube/config stays as it was).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
# shellcheck source=scripts/lib/platform.sh
source "$REPO_ROOT/scripts/lib/platform.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

ALB_CHART_OCI="oci://mcr.microsoft.com/application-lb/charts/alb-controller"
ESO_CHART_REPO="https://charts.external-secrets.io"
OTEL_CHART_REPO="https://open-telemetry.github.io/opentelemetry-helm-charts"
ALB_NAMESPACE=azure-alb-system
ESO_NAMESPACE=external-secrets
OTEL_NAMESPACE=observability
GATEWAY_CLASS=azure-alb-external
SECRET_STORE=azure-key-vault
GATEWAY_CLASS_WAIT_SECONDS="${GATEWAY_CLASS_WAIT_SECONDS:-300}"
WORK_DIR=""
PROFILE=core
OWNER=""
GATEWAY_API_RELEASES=https://github.com/kubernetes-sigs/gateway-api/releases/download
PLATFORM_VAULT=""
PLATFORM_DEPLOYERS=""
ACR_LOGIN_SERVER=""
AGC_SUBNET_CIDR=""
VELERO_CLIENT_ID=""
TRIVY_CLIENT_ID=""
KYVERNO_CLIENT_ID=""
VELERO_STORAGE_ACCOUNT_URI=""
AZURE_SUBSCRIPTION_ID=""
AKS_NODE_RESOURCE_GROUP=""

usage() {
  echo "usage: $0 [--profile core|full] [--github-owner OWNER]" >&2
  exit 2
}

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# load_platform_versions -> reads platform/versions.env (KEY=VALUE lines) without executing it.
load_platform_versions() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" =~ ^([A-Z0-9_]+)=([A-Za-z0-9._:/-]+)$ ]] || die "invalid line in platform/versions.env: $line"
    printf -v "${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
  done <"$HERE/versions.env"
}

# identity_client_id NAME -> client ID of a user-assigned identity of the lab resource group.
identity_client_id() {
  local rg=$1 name=$2 id
  id="$(az identity show --resource-group "$rg" --name "$name" --query clientId --output tsv)" ||
    die "cannot read the identity $name in $rg (did terraform apply of terraform/envs/lab run?)"
  [[ "$id" =~ $GUID_RE ]] || die "the client ID of $name is not a GUID"
  printf '%s' "$id"
}

# connect_cluster RG CLUSTER -> temporary kubeconfig that authenticates with the Entra ID tokens of
# the Azure CLI session (local accounts are disabled); the user's own kubeconfig is never touched.
connect_cluster() {
  local rg=$1 cluster=$2
  export KUBECONFIG="$WORK_DIR/kubeconfig"
  az aks get-credentials --resource-group "$rg" --name "$cluster" --file "$KUBECONFIG" --overwrite-existing --only-show-errors >/dev/null ||
    die "cannot fetch the kubeconfig of $cluster (this identity needs AKS Cluster User Role or Contributor on it)"
  kubelogin convert-kubeconfig -l azurecli --kubeconfig "$KUBECONFIG"
  kubectl get --raw /readyz >/dev/null ||
    die "the API server of $cluster is not reachable from here (api_server_authorized_ip_ranges) or this identity is not in cluster_admin_principal_ids"
}

# alb_image_digests -> one line per ALB Controller pod: "<pod>|<deletionTimestamp>|<container>=<imageID> ...".
alb_image_digests() {
  kubectl --namespace "$ALB_NAMESPACE" get pods --selector app=alb-controller --output jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.deletionTimestamp}{"|"}{range .status.initContainerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{range .status.containerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{"\n"}{end}'
}

# verify_alb_images -> the chart gives its three images one shared tag (no digest pinning), so the
# digests the nodes actually pulled are compared with platform/versions.env (index or amd64
# manifest). Pods already terminating (the previous release during an upgrade) are not checked.
verify_alb_images() {
  local out pod deleting containers entry checked=0 bad=0
  out="$(alb_image_digests)" || die "cannot read the ALB Controller pods"
  while IFS='|' read -r pod deleting containers; do
    [[ -n "$pod" && -z "$deleting" ]] || continue
    for entry in $containers; do
      verify_alb_image "${entry%%=*}" "${entry#*=}" || bad=$((bad + 1))
      checked=$((checked + 1))
    done
  done <<<"$out"
  ((checked >= 3)) || die "found $checked ALB Controller containers with an image digest (expected at least 3)"
  ((bad == 0)) ||
    die "the ALB Controller runs images that differ from platform/versions.env: remove it (platform/uninstall.sh) and review the release before trusting it"
  log "ALB Controller images verified ($checked containers, digests from platform/versions.env)"
}

# verify_alb_image CONTAINER IMAGE_ID -> success when the pulled digest is one of platform/versions.env.
verify_alb_image() {
  local name=$1 image_id=$2 digest want
  digest="${image_id##*@sha256:}"
  case "$name" in
    alb-controller) want="$ALB_CONTROLLER_IMAGE_SHA256 $ALB_CONTROLLER_IMAGE_AMD64_SHA256" ;;
    init-alb-controller-bootstrap) want="$ALB_CONTROLLER_BOOTSTRAP_IMAGE_SHA256 $ALB_CONTROLLER_BOOTSTRAP_IMAGE_AMD64_SHA256" ;;
    init-alb-controller-crds) want="$ALB_CONTROLLER_CRDS_IMAGE_SHA256 $ALB_CONTROLLER_CRDS_IMAGE_AMD64_SHA256" ;;
    *) die "unexpected container '$name' in the ALB Controller pods (review the chart before upgrading)" ;;
  esac
  if [[ ! "$digest" =~ ^[0-9a-f]{64}$ || " $want " != *" $digest "* ]]; then
    log "container $name runs $image_id, platform/versions.env expects sha256 ${want// / or }"
    return 1
  fi
}

install_alb_controller() {
  local client_id=$1 tgz
  tgz="$WORK_DIR/alb-controller-$ALB_CONTROLLER_CHART_VERSION.tgz"
  helm pull "$ALB_CHART_OCI" --version "$ALB_CONTROLLER_CHART_VERSION" --destination "$WORK_DIR"
  [[ -f "$tgz" ]] || die "helm pull did not produce $(basename "$tgz")"
  [[ "$(sha256_of "$tgz")" == "$ALB_CONTROLLER_CHART_SHA256" ]] ||
    die "refusing the ALB Controller chart $ALB_CONTROLLER_CHART_VERSION: its SHA256 differs from platform/versions.env"
  log "installing the ALB Controller chart $ALB_CONTROLLER_CHART_VERSION (SHA256 verified)"
  # The release lives in the controller namespace, so the chart renders no Namespace of its own.
  helm upgrade --install alb-controller "$tgz" \
    --namespace "$ALB_NAMESPACE" --create-namespace \
    --values "$HERE/values/alb-controller.yaml" \
    --set-string albController.podIdentity.clientID="$client_id" \
    --wait=watcher --rollback-on-failure --timeout 10m
  verify_alb_images
}

# The bootstrap init container of the ALB Controller creates the GatewayClass; the controller then
# accepts it.
wait_for_gateway_class() {
  local deadline=$((SECONDS + GATEWAY_CLASS_WAIT_SECONDS)) out
  while :; do
    out="$(kubectl get gatewayclass "$GATEWAY_CLASS" --ignore-not-found --output name)" ||
      die "cannot query GatewayClass $GATEWAY_CLASS"
    [[ -z "$out" ]] || break
    ((SECONDS < deadline)) || die "GatewayClass $GATEWAY_CLASS did not appear within ${GATEWAY_CLASS_WAIT_SECONDS}s"
    log "waiting for GatewayClass $GATEWAY_CLASS"
    sleep 10
  done
  kubectl wait --for=condition=Accepted "gatewayclass/$GATEWAY_CLASS" --timeout=300s
}

install_external_secrets() {
  local client_id=$1 tenant=$2
  log "installing the external-secrets chart $ESO_CHART_VERSION"
  helm upgrade --install external-secrets external-secrets \
    --repo "$ESO_CHART_REPO" --version "$ESO_CHART_VERSION" \
    --namespace "$ESO_NAMESPACE" --create-namespace \
    --values "$HERE/values/external-secrets.yaml" \
    --set-string "serviceAccount.annotations.azure\.workload\.identity/client-id=$client_id" \
    --set-string "serviceAccount.annotations.azure\.workload\.identity/tenant-id=$tenant" \
    --wait=watcher --rollback-on-failure --timeout 10m
}

# traces_connection_string RG -> connection string of the Application Insights tx02v2-lab-traces.
traces_connection_string() {
  local rg=$1 cs
  cs="$(az resource show --resource-group "$rg" --name "$LAB_NAME-traces" --resource-type Microsoft.Insights/components \
    --query properties.ConnectionString --output tsv)" ||
    die "cannot read the Application Insights $LAB_NAME-traces in $rg (did terraform apply of terraform/envs/lab run?)"
  [[ "$cs" =~ ^InstrumentationKey=[0-9a-f-]{36}\;IngestionEndpoint=https://[A-Za-z0-9.-]+/ ]] ||
    die "the connection string of $LAB_NAME-traces is not in the expected form"
  printf '%s' "$cs"
}

# The Collector reads the connection string from a ConfigMap (stdin, never an argument); its
# Workload ID client-id annotation comes from tx02v2-lab-otel.
install_otel_collector() {
  local client_id=$1 connection_string=$2 tgz
  tgz="$WORK_DIR/opentelemetry-collector-$OTEL_COLLECTOR_CHART_VERSION.tgz"
  helm pull opentelemetry-collector --repo "$OTEL_CHART_REPO" --version "$OTEL_COLLECTOR_CHART_VERSION" --destination "$WORK_DIR"
  [[ -f "$tgz" && "$(sha256_of "$tgz")" == "$OTEL_COLLECTOR_CHART_SHA256" ]] ||
    die "refusing the opentelemetry-collector chart $OTEL_COLLECTOR_CHART_VERSION: missing, or its SHA256 differs from platform/versions.env"
  printf '%s' "$connection_string" | kubectl --namespace "$OTEL_NAMESPACE" create configmap otel-collector-azure-monitor \
    --from-file=connection-string=/dev/stdin --dry-run=client --output yaml | kubectl apply -f - >/dev/null
  log "installing the opentelemetry-collector chart $OTEL_COLLECTOR_CHART_VERSION (SHA256 verified; traces to Application Insights $LAB_NAME-traces)"
  helm upgrade --install opentelemetry-collector "$tgz" \
    --namespace "$OTEL_NAMESPACE" \
    --values "$HERE/values/otel-collector.yaml" \
    --set-string "serviceAccount.annotations.azure\.workload\.identity/client-id=$client_id" \
    --wait=watcher --rollback-on-failure --timeout 10m
}

apply_manifests() {
  local file=$1 attempt
  # The ESO admission webhook can need a few seconds after `helm --wait` to serve its certificate.
  for attempt in 1 2 3 4 5; do
    if kubectl apply -f "$file"; then
      return 0
    fi
    log "kubectl apply failed (attempt $attempt/5); retrying in 15 s"
    sleep 15
  done
  die "could not apply platform/manifests"
}

# apply_full FILE -> applies one full-profile manifest after its CRDs exist.
apply_full() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$HERE/render-manifests.sh" "$PLATFORM_VAULT" "$PLATFORM_DEPLOYERS" \
      --full "$OWNER" --acr-login-server "$ACR_LOGIN_SERVER" --agc-subnet-cidr "$AGC_SUBNET_CIDR" \
      --only "$1" | kubectl apply -f - >/dev/null; then
      return 0
    fi
    log "kubectl apply of platform/manifests/$1 failed (attempt $attempt/5); retrying in 15 s"
    sleep 15
  done
  die "could not apply platform/manifests/$1"
}

# install_chart CHART [HELM_ARG...] -> installs one pinned chart from platform/full/charts.txt.
# Install-time values are rendered to the temporary work directory; no cloud ID enters the repo.
install_chart() {
  local chart=$1 repo_key version_key sha_key name release ns values tgz f out content
  local -a files=() args=()
  shift
  read -r repo_key version_key sha_key name release ns values <<<"$(chart_entry "$chart")"
  IFS=, read -ra files <<<"$values"
  mkdir -p "$WORK_DIR/values/$chart"
  for f in "${files[@]}"; do
    [[ -f "$HERE/$f" ]] || die "platform/full/charts.txt: platform/$f does not exist"
    out="$WORK_DIR/values/$chart/$(printf '%02d' "${#args[@]}")-$(basename "$f")"
    content="$(<"$HERE/$f")"
    content="${content//__VELERO_CLIENT_ID__/$VELERO_CLIENT_ID}"
    content="${content//__TRIVY_CLIENT_ID__/$TRIVY_CLIENT_ID}"
    content="${content//__KYVERNO_CLIENT_ID__/$KYVERNO_CLIENT_ID}"
    content="${content//__VELERO_STORAGE_ACCOUNT_URI__/$VELERO_STORAGE_ACCOUNT_URI}"
    content="${content//__AZURE_SUBSCRIPTION_ID__/$AZURE_SUBSCRIPTION_ID}"
    content="${content//__AKS_NODE_RESOURCE_GROUP__/$AKS_NODE_RESOURCE_GROUP}"
    content="${content//__S3_BUCKET__/tx02v2-lab-velero}"
    content="${content//__S3_ENDPOINT__/$VELERO_STORAGE_ACCOUNT_URI}"
    if [[ "$content" =~ __[A-Z][A-Z0-9_]*__ ]]; then
      die "unresolved install-time placeholder ${BASH_REMATCH[0]} in platform/$f"
    fi
    printf '%s\n' "$content" >"$out"
    args+=(--values "$out")
  done
  tgz="$(pull_chart "$WORK_DIR/charts" "${!repo_key}" "$name" "${!version_key}" "${!sha_key}")"
  log "installing $release ($name ${!version_key}, SHA256 verified) in $ns"
  helm upgrade --install "$release" "$tgz" --namespace "$ns" --create-namespace "${args[@]}" "$@" \
    --wait=watcher --rollback-on-failure --timeout 10m >/dev/null
}

install_istio() {
  local asset="$WORK_DIR/gateway-api-$GATEWAY_CRDS_VERSION-experimental.yaml" got
  download "$GATEWAY_API_RELEASES/$GATEWAY_CRDS_VERSION/experimental-install.yaml" "$asset"
  got="$(sha256_of "$asset")"
  [[ "$got" == "$GATEWAY_CRDS_EXPERIMENTAL_SHA256" ]] || die "refusing experimental Gateway API $GATEWAY_CRDS_VERSION: SHA256 differs from platform/local/versions.env"
  kubectl apply --server-side --force-conflicts -f "$asset" >/dev/null
  kubectl wait --for=condition=Established --timeout=120s \
    crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io >/dev/null
  install_chart base
  install_chart istiod
  install_chart cni
  install_chart ztunnel
  retry 60 2 kubectl get gatewayclass istio >/dev/null 2>&1 || die "istiod did not create the GatewayClass istio"
  retry 60 2 kubectl get gatewayclass istio-waypoint >/dev/null 2>&1 || die "istiod did not create the GatewayClass istio-waypoint"
}

install_waypoint() {
  apply_full full/waypoint.yaml
  kubectl wait --namespace dx02v2 --for=condition=Programmed gateway/dx02v2-waypoint --timeout=300s >/dev/null ||
    die "Istio did not program the dx02v2 ambient waypoint"
  kubectl label namespace dx02v2 istio.io/use-waypoint=dx02v2-waypoint --overwrite >/dev/null
}

install_observability() {
  local hook="${SLACK_WEBHOOK_URL:-}"
  local -a slack=()
  if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    openssl rand -hex 16 | tr -d '\n' | kubectl -n monitoring create secret generic grafana-admin \
      --from-literal=admin-user=admin --from-file=admin-password=/dev/stdin >/dev/null
  fi
  if [[ -n "$hook" ]]; then
    [[ "$hook" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9/_-]+$ ]] || die "SLACK_WEBHOOK_URL must be an https Slack incoming webhook"
    printf '%s' "$hook" | kubectl -n monitoring create secret generic alertmanager-slack \
      --from-file=webhook-url=/dev/stdin --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    slack=(--values "$HERE/values/full/kube-prometheus-stack-slack.yaml")
  fi
  if ! helm -n monitoring status kube-prometheus-stack >/dev/null 2>&1; then
    install_chart kube-prometheus-stack "${slack[@]}" --set defaultRules.create=false
  fi
  kubectl -n monitoring rollout status deployment/kube-prometheus-stack-operator --timeout=300s >/dev/null
  install_chart kube-prometheus-stack "${slack[@]}"
  retry 30 5 kubectl -n monitoring get statefulset prometheus-kube-prometheus-stack-prometheus alertmanager-kube-prometheus-stack-alertmanager >/dev/null 2>&1 ||
    die "the Prometheus Operator did not create Prometheus and Alertmanager"
  kubectl -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout=300s >/dev/null
  kubectl -n monitoring rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager --timeout=300s >/dev/null
  install_chart loki
  install_chart alloy
  install_chart tempo
  install_chart opentelemetry-collector
  apply_full full/tracing.yaml
}

install_gitops() {
  install_chart argo-cd
  kubectl wait --for=condition=Established --timeout=120s crd/applications.argoproj.io crd/appprojects.argoproj.io >/dev/null
  apply_full full/argocd-platform.yaml
  apply_full full/rbac-argocd-deployer.yaml
}

install_policies() {
  local kind f repos="$WORK_DIR/allowed-repos.yaml"
  install_chart gatekeeper
  retry 10 6 kubectl apply -f "$HERE/local/policies/templates/" >/dev/null || die "could not apply Gatekeeper ConstraintTemplates"
  while read -r kind; do
    retry 30 2 kubectl get crd "${kind,,}.constraints.gatekeeper.sh" >/dev/null 2>&1 || die "Gatekeeper did not create the CRD of $kind"
    kubectl wait --for=condition=Established "crd/${kind,,}.constraints.gatekeeper.sh" --timeout=60s >/dev/null
  done < <(sed -n 's/^        kind: \(Lab[A-Za-z]*\)$/\1/p' "$HERE"/local/policies/templates/*.yaml)
  for f in "$HERE"/local/policies/constraints/*.yaml; do
    [[ "$(basename "$f")" != allowed-repos.yaml ]] || continue
    retry 10 6 kubectl apply -f "$f" >/dev/null || die "could not apply Gatekeeper constraint $(basename "$f")"
  done
  sed "s|__ACR_LOGIN_SERVER__|$ACR_LOGIN_SERVER|g" "$HERE/full/policies/constraints/allowed-repos.yaml" >"$repos"
  retry 10 6 kubectl apply -f "$repos" >/dev/null || die "could not apply the Gatekeeper constraint allowed-repos"
}

install_image_admission() {
  install_chart kyverno
  kubectl wait --for=condition=Established --timeout=180s \
    crd/imagevalidatingpolicies.policies.kyverno.io >/dev/null
  kubectl --namespace kyverno rollout status deployment/kyverno-admission-controller --timeout=300s >/dev/null ||
    die "Kyverno's admission controller is not ready; image verification stays fail-closed"
  apply_full full/image-verification.yaml
}

install_backup() {
  install_chart velero
  # shellcheck disable=SC2016 # expanded by the inner bash
  retry 30 5 bash -c '[[ "$(kubectl -n velero get backupstoragelocation default -o jsonpath="{.status.phase}")" == Available ]]' ||
    die "Velero: the Blob backup location is not Available (check the Workload Identity and container-scoped role assignment)"
}

install_full() {
  local rg=$1 cluster=$2 sub storage_name storage_endpoint value
  require_cmd openssl curl
  load_pins "$HERE/local/versions.env"
  sub="$(subscription_id)" || die "cannot read the active Azure subscription ID"
  AZURE_SUBSCRIPTION_ID="$sub"
  AKS_NODE_RESOURCE_GROUP="$(az aks show --resource-group "$rg" --name "$cluster" --query nodeResourceGroup --output tsv)" ||
    die "cannot read the AKS node resource group for the Azure Workload Identity plugin"
  [[ "$AKS_NODE_RESOURCE_GROUP" =~ ^[A-Za-z0-9._()-]{1,90}$ ]] || die "AKS returned an invalid node resource group name"
  VELERO_CLIENT_ID="$(identity_client_id "$rg" "$LAB_NAME-velero")"
  TRIVY_CLIENT_ID="$(identity_client_id "$rg" "$LAB_NAME-trivy")"
  KYVERNO_CLIENT_ID="$(identity_client_id "$rg" "$LAB_NAME-kyverno")"
  storage_name="${LAB_NAME//-/}$(lab_suffix "$sub")velero"
  storage_endpoint="$(az storage account show --resource-group "$rg" --name "$storage_name" --query primaryEndpoints.blob --output tsv)" ||
    die "cannot read the Blob endpoint of $storage_name"
  [[ "$storage_endpoint" =~ ^https://[A-Za-z0-9.-]+/ ]] || die "the Storage account returned an invalid Blob endpoint"
  VELERO_STORAGE_ACCOUNT_URI="${storage_endpoint%/}"
  ACR_LOGIN_SERVER="$(contract acr/login-server)"
  [[ "$ACR_LOGIN_SERVER" =~ ^[a-z0-9]{5,50}\.azurecr\.io$ ]] || die "contract key acr/login-server is not an ACR login server"
  AGC_SUBNET_CIDR="$(contract agc-subnet-cidr)"
  [[ "$AGC_SUBNET_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/24$ ]] || die "contract key agc-subnet-cidr is not an IPv4 /24"
  for value in "$AZURE_SUBSCRIPTION_ID" "$AKS_NODE_RESOURCE_GROUP" "$VELERO_CLIENT_ID" "$TRIVY_CLIENT_ID" "$KYVERNO_CLIENT_ID" "$VELERO_STORAGE_ACCOUNT_URI"; do mask "$value"; done

  apply_full full/namespaces.yaml
  install_istio
  install_waypoint
  apply_full full/app-security.yaml
  install_chart cert-manager
  install_observability
  apply_full full/app-monitoring.yaml
  install_policies
  install_image_admission
  install_gitops
  install_chart trivy-operator
  install_backup
  install_chart chaos-mesh
  log "profile full ready: $(helm list --all-namespaces --short | sort | tr '\n' ' ')"
}

main() {
  while (($# > 0)); do
    case "$1" in
      --profile)
        [[ "${2:-}" == core || "${2:-}" == full ]] || usage
        PROFILE=$2
        shift 2
        ;;
      --github-owner)
        [[ "${2:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || usage
        OWNER=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [[ "$PROFILE" == core || -n "$OWNER" ]] || die "profile full needs --github-owner (the GitHub user or organization of your forks)"
  local rg cluster vault deployer store tenant alb_client eso_client otel_client traces id deployers extra
  require_cmd az kubectl helm kubelogin
  require_az_login
  load_platform_versions
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT
  mkdir -p "$WORK_DIR/helm/config" "$WORK_DIR/helm/cache" "$WORK_DIR/helm/data"
  export HELM_CONFIG_HOME="$WORK_DIR/helm/config" HELM_CACHE_HOME="$WORK_DIR/helm/cache" HELM_DATA_HOME="$WORK_DIR/helm/data"

  load_contract
  rg="$(contract resource-group)"
  cluster="$(contract cluster-name)"
  [[ "$rg" == "$LAB_NAME" && "$cluster" == "$LAB_NAME" ]] ||
    die "contract keys resource-group and cluster-name are '$rg' and '$cluster', not $LAB_NAME"
  require_lab_cluster "$rg" "$cluster"
  vault="$(contract keyvault/uri)"
  deployer="$(contract deploy/principal-id)"
  store="$(contract eso/cluster-secret-store)"
  [[ "$store" == "$SECRET_STORE" ]] ||
    die "contract key ${LAB_KEY_PREFIX}eso/cluster-secret-store is '$store' but platform/manifests creates $SECRET_STORE"
  [[ "$deployer" =~ $GUID_RE ]] || die "contract key ${LAB_KEY_PREFIX}deploy/principal-id is not an object ID"
  mask "$deployer"
  deployers="$deployer"
  extra="$(guids_from_json_list "${APP_DEPLOYER_PRINCIPAL_IDS:-[]}")" ||
    die "APP_DEPLOYER_PRINCIPAL_IDS must be a JSON list of object IDs, e.g. [] (the Terraform variable app_deployer_principal_ids)"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    mask "$id"
    deployers+=",$id"
  done <<<"$extra"
  PLATFORM_VAULT="$vault"
  PLATFORM_DEPLOYERS="$deployers"
  tenant="$(tenant_id)" || die "cannot read the tenant of the Azure CLI session"
  mask "$tenant"
  alb_client="$(identity_client_id "$rg" "$LAB_NAME-alb")"
  eso_client="$(identity_client_id "$rg" "$LAB_NAME-eso")"
  otel_client="$(identity_client_id "$rg" "$LAB_NAME-otel")"
  traces="$(traces_connection_string "$rg")"
  mask "$alb_client"
  mask "$eso_client"
  mask "$otel_client"
  mask "$traces"

  # Rendered before anything is installed: a malformed contract value stops the script here.
  "$HERE/render-manifests.sh" "$vault" "$deployers" >"$WORK_DIR/manifests.yaml"

  log "cluster $cluster in resource group $rg"
  connect_cluster "$rg" "$cluster"
  install_alb_controller "$alb_client"
  wait_for_gateway_class
  install_external_secrets "$eso_client" "$tenant"
  log "applying platform/manifests"
  apply_manifests "$WORK_DIR/manifests.yaml"
  install_otel_collector "$otel_client" "$traces"
  # Ready means ESO reached Key Vault with the Workload ID token of tx02v2-lab-eso.
  kubectl wait --for=condition=Ready "clustersecretstore/$store" --timeout=180s
  log "platform ready: GatewayClass $GATEWAY_CLASS, ClusterSecretStore $store, namespace dx02v2, OTLP endpoint opentelemetry-collector.$OTEL_NAMESPACE.svc:4318"
  if [[ "$PROFILE" == full ]]; then
    install_full "$rg" "$cluster"
  fi
}

main "$@"
