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
#   4. stops Argo CD reconciliation before removing routes, then uninstalls the full profile releases
#      (when present) and the External Secrets Operator and ALB Controller
#      releases.
# CLOUD-MUTATING. Fails loudly on any error or timeout. Needs the same tools as platform/install.sh.
# The resource group and the cluster are the contract names (tx02v2-lab), so the teardown does not
# depend on App Configuration. No environment variable changes them (a shell may export
# RESOURCE_GROUP or CLUSTER_NAME for other work), and the cluster must carry the tag Project=tx02v2:
# this script deletes every Route, Gateway and LoadBalancer Service of the cluster it reaches.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"
# shellcheck source=scripts/lib/azure.sh
source "$REPO_ROOT/scripts/lib/azure.sh"
export PATH="$REPO_ROOT/.tools/bin:$PATH"

RESOURCE_GROUP=$LAB_NAME
CLUSTER_NAME=$LAB_NAME
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

# stop_gitops -> stop both Applications before deleting routes. The parent syncs the GitOps chart;
# deleting it first prevents it from recreating the dx02v2 Application while the child is removed.
stop_gitops() {
  crd_exists applications.argoproj.io || return 0
  log "stopping the Argo CD app-of-apps and dx02v2 Application"
  kubectl delete applications.argoproj.io platform --namespace argocd --ignore-not-found --wait=true --timeout=5m
  kubectl delete applications.argoproj.io dx02v2 --namespace argocd --ignore-not-found --wait=true --timeout=5m
  kubectl delete appprojects.argoproj.io platform dx02v2 --namespace argocd --ignore-not-found --wait=true --timeout=5m
}

uninstall_full_releases() {
  helm uninstall chaos-mesh --namespace chaos-mesh --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall velero --namespace velero --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall trivy-operator --namespace trivy-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall kyverno --namespace kyverno --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall gatekeeper --namespace gatekeeper-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall argo-cd --namespace argocd --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall opentelemetry-collector --namespace observability --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall tempo --namespace monitoring --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall alloy --namespace monitoring --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall loki --namespace monitoring --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall kube-prometheus-stack --namespace monitoring --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall ztunnel --namespace istio-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall istio-cni --namespace istio-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall istiod --namespace istio-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall istio-base --namespace istio-system --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall cert-manager --namespace cert-manager --ignore-not-found --wait=watcher --timeout 10m
}

remove_waypoint() {
  local waypoint
  if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    kubectl delete gateway --namespace dx02v2 dx02v2-waypoint --ignore-not-found --wait=true --timeout=5m
  fi
  if kubectl get namespace dx02v2 >/dev/null 2>&1; then
    waypoint="$(kubectl get namespace dx02v2 -o jsonpath='{.metadata.labels.istio\.io/use-waypoint}')"
    if [[ "$waypoint" == dx02v2-waypoint ]]; then
      kubectl label namespace dx02v2 istio.io/use-waypoint- >/dev/null
    fi
  fi
}

remove_full_application_resources() {
  # These resources are applied directly by the full profile rather than owned by a Helm release.
  # Remove them while their CRDs still exist so a later core-profile install has no stale policies,
  # SLO rules, or dashboard from the full profile.
  if crd_exists peerauthentications.security.istio.io; then
    kubectl delete peerauthentications.security.istio.io default agc-edge-web agc-edge-api agc-edge-acme-solver \
      --namespace dx02v2 --ignore-not-found --wait=true --timeout=5m
  fi
  if crd_exists authorizationpolicies.security.istio.io; then
    kubectl delete authorizationpolicies.security.istio.io api web-agc-edge api-require-waypoint \
      --namespace dx02v2 --ignore-not-found --wait=true --timeout=5m
  fi
  if crd_exists servicemonitors.monitoring.coreos.com; then
    kubectl delete servicemonitors.monitoring.coreos.com dx02v2-api --namespace monitoring \
      --ignore-not-found --wait=true --timeout=5m
  fi
  if crd_exists prometheusrules.monitoring.coreos.com; then
    kubectl delete prometheusrules.monitoring.coreos.com dx02v2-slo --namespace monitoring \
      --ignore-not-found --wait=true --timeout=5m
  fi
  kubectl delete configmap dx02v2-api-dashboard --namespace monitoring \
    --ignore-not-found --wait=true --timeout=5m
}

delete_full_persistent_volume_claims() {
  local namespace left
  namespace="$(kubectl get namespace monitoring --ignore-not-found --output name)" ||
    die "cannot check the monitoring namespace before deleting PVCs"
  [[ -n "$namespace" ]] || return 0
  left="$(kubectl get pvc --namespace monitoring --output name)" || die "cannot list monitoring PVCs"
  [[ -z "$left" ]] && return 0
  log "deleting monitoring PVCs (AKS managed-csi disks)"
  kubectl delete pvc --namespace monitoring --all --wait=true --timeout=10m
  left="$(kubectl get pvc --namespace monitoring --output name)" || die "cannot list monitoring PVCs after deletion"
  [[ -z "$left" ]] || die "monitoring PVCs remain after uninstall:"$'\n'"$left"
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
  require_lab_cluster "$RESOURCE_GROUP" "$CLUSTER_NAME"
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  export KUBECONFIG="$WORK_DIR/kubeconfig"
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --file "$KUBECONFIG" --overwrite-existing --only-show-errors >/dev/null ||
    die "cannot fetch the kubeconfig of $CLUSTER_NAME"
  kubelogin convert-kubeconfig -l azurecli --kubeconfig "$KUBECONFIG"
  kubectl get --raw /readyz >/dev/null ||
    die "the API server of $CLUSTER_NAME is not reachable from here (api_server_authorized_ip_ranges) or this identity is not in cluster_admin_principal_ids"

  stop_gitops

  # The TLS material belongs to this lab, including the ACME account key. Remove it while
  # cert-manager is still running, then remove the routes and its release below.
  if crd_exists certificates.cert-manager.io; then
    kubectl delete certificate dx02v2-tls --namespace dx02v2 --ignore-not-found --wait=true --timeout=5m
  fi
  if crd_exists clusterissuers.cert-manager.io; then
    kubectl delete clusterissuer tx02v2-letsencrypt-prod --ignore-not-found --wait=true --timeout=5m
  fi
  kubectl delete secret dx02v2-tls --namespace dx02v2 --ignore-not-found --wait=true --timeout=5m
  kubectl delete secret tx02v2-letsencrypt-account --namespace cert-manager --ignore-not-found --wait=true --timeout=5m

  remove_full_application_resources
  remove_waypoint
  delete_all imagevalidatingpolicies.policies.kyverno.io
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
  uninstall_full_releases
  delete_full_persistent_volume_claims
  helm uninstall external-secrets --namespace external-secrets --ignore-not-found --wait=watcher --timeout 10m
  helm uninstall alb-controller --namespace azure-alb-system --ignore-not-found --wait=watcher --timeout 10m
  log "platform removed from $CLUSTER_NAME"
}

main "$@"
