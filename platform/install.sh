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

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# load_platform_versions -> reads platform/versions.env (KEY=VALUE lines) without executing it.
load_platform_versions() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" =~ ^([A-Z0-9_]+)=([A-Za-z0-9._-]+)$ ]] || die "invalid line in platform/versions.env: $line"
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

main() {
  (($# == 0)) || die "usage: $0 (configuration through environment variables, see the header)"
  local rg cluster vault deployer store tenant alb_client eso_client otel_client traces id deployers extra
  require_cmd az kubectl helm kubelogin
  require_az_login
  load_platform_versions
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

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
}

main "$@"
