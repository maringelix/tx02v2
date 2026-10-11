#!/usr/bin/env bash
# Removes the platform layer before `terraform destroy`:
#   1. deletes every HTTPRoute, GRPCRoute and Gateway in the cluster, the ALB policies
#      (alb.networking.azure.io) and the Ingresses of class azure-alb-external, and waits until
#      they are gone: the ALB Controller removes their configuration from Application Gateway for
#      Containers and then their finalizers, so it must still be running;
#   2. in the bring-your-own deployment of this lab the controller owns no Azure resource (the AGC,
#      its frontend and its subnet association belong to Terraform). If ApplicationLoadBalancer
#      objects exist (an ALB-managed deployment someone added by hand), deletes them and waits
#      until the AGC resources the controller created for them are gone from Azure;
#   3. deletes Services of type LoadBalancer (their public IPs live in the AKS node resource group);
#   4. uninstalls the External Secrets Operator and the ALB Controller releases.
# CLOUD-MUTATING. Fails loudly on any error or timeout. Needs the same tools as platform/install.sh.
# RESOURCE_GROUP and CLUSTER_NAME default to the contract names (tx02v2-lab): the teardown does
# not depend on App Configuration.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

RESOURCE_GROUP="${RESOURCE_GROUP:-$LAB_NAME}"
CLUSTER_NAME="${CLUSTER_NAME:-$LAB_NAME}"
AGC_WAIT_SECONDS="${AGC_WAIT_SECONDS:-900}"
GATEWAY_CLASS=azure-alb-external
ALB_LB_CRD=applicationloadbalancers.alb.networking.azure.io
WORK_DIR=""

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

# crd_exists NAME -> success when the CRD is installed. API errors are fatal, never "not found".
crd_exists() {
  local out
  out="$(kubectl get crd "$1" --ignore-not-found --output name)" || die "cannot query the CRD $1"
  [[ -n "$out" ]]
}

# delete_all RESOURCE -> deletes every object of RESOURCE (plural.group) in every namespace and
# waits for their finalizers; then proves that none is left.
delete_all() {
  local resource=$1 left
  crd_exists "$resource" || return 0
  log "deleting every $resource"
  kubectl delete "$resource" --all --all-namespaces --wait=true --timeout=10m
  left="$(kubectl get "$resource" --all-namespaces --output name)" || die "cannot list $resource"
  [[ -z "$left" ]] || die "still present after the delete:"$'\n'"$left"
}

delete_alb_ingresses() {
  local out ing
  out="$(kubectl get ingress --all-namespaces \
    --output jsonpath="{range .items[?(@.spec.ingressClassName==\"$GATEWAY_CLASS\")]}{.metadata.namespace}{\"/\"}{.metadata.name}{\"\\n\"}{end}")" ||
    die "cannot list the Ingresses"
  while IFS= read -r ing; do
    [[ -n "$ing" ]] || continue
    log "deleting Ingress $ing (class $GATEWAY_CLASS)"
    kubectl delete ingress --namespace "${ing%%/*}" "${ing#*/}" --wait=true --timeout=10m
  done <<<"$out"
}

delete_load_balancer_services() {
  local out svc
  out="$(kubectl get services --all-namespaces \
    --output jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')" ||
    die "cannot list the Services"
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    log "deleting Service $svc (type LoadBalancer)"
    kubectl delete service --namespace "${svc%%/*}" "${svc#*/}" --wait=true --timeout=5m
  done <<<"$out"
}

# controller_agcs NODE_RG -> Application Gateway for Containers resources the controller created
# (ALB-managed deployment) that still exist, one per line.
controller_agcs() {
  az resource list --resource-group "$1" --resource-type Microsoft.ServiceNetworking/trafficControllers \
    --query '[].id' --output tsv | words_to_lines
}

delete_managed_application_load_balancers() {
  local albs node_rg deadline remaining
  crd_exists "$ALB_LB_CRD" || return 0
  albs="$(kubectl get "$ALB_LB_CRD" --all-namespaces --output name)" || die "cannot list $ALB_LB_CRD"
  [[ -n "$albs" ]] || return 0
  node_rg="$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query nodeResourceGroup --output tsv)" ||
    die "cannot read the node resource group of $CLUSTER_NAME"
  log "ALB-managed deployment found: deleting $(wc -l <<<"$albs") ApplicationLoadBalancer object(s)"
  kubectl delete "$ALB_LB_CRD" --all --all-namespaces --wait=true --timeout=15m
  deadline=$((SECONDS + AGC_WAIT_SECONDS))
  while :; do
    remaining="$(controller_agcs "$node_rg")" || die "cannot list the AGC resources of $node_rg"
    if [[ -z "$remaining" ]]; then
      log "no Application Gateway for Containers left in the node resource group"
      return 0
    fi
    ((SECONDS < deadline)) ||
      die "Application Gateway for Containers created by the controller still present after ${AGC_WAIT_SECONDS}s ($(wc -l <<<"$remaining") resource(s) in the node resource group)"
    log "waiting for $(wc -l <<<"$remaining") controller-owned AGC resource(s) to be deleted"
    sleep 30
  done
}

main() {
  (($# == 0)) || die "usage: $0 (configuration through environment variables, see the header)"
  local crds crd
  require_cmd az kubectl helm kubelogin
  require_az_login
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  export KUBECONFIG="$WORK_DIR/kubeconfig"
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --file "$KUBECONFIG" --overwrite-existing --only-show-errors >/dev/null ||
    die "cannot fetch the kubeconfig of $CLUSTER_NAME"
  kubelogin convert-kubeconfig -l azurecli --kubeconfig "$KUBECONFIG"
  kubectl get --raw /readyz >/dev/null ||
    die "the API server of $CLUSTER_NAME is not reachable from here (api_server_authorized_ip_ranges) or this identity is not in cluster_admin_principal_ids"

  # Routes first, then the Gateways they attach to, then the policies that target either.
  delete_all httproutes.gateway.networking.k8s.io
  delete_all grpcroutes.gateway.networking.k8s.io
  delete_all gateways.gateway.networking.k8s.io
  crds="$(kubectl get crd --output name)" || die "cannot list the CRDs"
  while IFS= read -r crd; do
    crd="${crd#customresourcedefinition.apiextensions.k8s.io/}"
    [[ "$crd" == *.alb.networking.azure.io && "$crd" != "$ALB_LB_CRD" ]] || continue
    delete_all "$crd"
  done <<<"$crds"
  delete_alb_ingresses
  delete_managed_application_load_balancers
  delete_load_balancer_services

  log "uninstalling the platform releases"
  helm uninstall external-secrets --namespace external-secrets --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall alb-controller --namespace azure-alb-system --ignore-not-found --wait=watcher --timeout 10m
  log "platform removed from $CLUSTER_NAME"
}

main "$@"
