#!/usr/bin/env bash
# Offline regression of the real core -> full installer functions; no Azure/Kubernetes access.
set -euo pipefail
# shellcheck source=platform/install.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../platform/install.sh"
require_cmd helm jq
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "${WORK_DIR:?}"' EXIT
mkdir -p "$WORK_DIR/parser/templates"
cat >"$WORK_DIR/parser/Chart.yaml" <<'YAML'
apiVersion: v2
name: installer-values-fixture
version: 0.1.0
YAML
cat >"$WORK_DIR/parser/templates/values.yaml" <<'TPL'
{{ .Values | toJson }}
TPL
load_platform_versions
load_pins "$HERE/local/versions.env"
OTEL_CLIENT_ID=00000000-0000-0000-0000-000000000000
: >"$WORK_DIR/opentelemetry-collector-$OTEL_COLLECTOR_CHART_VERSION.tgz"
OTEL_COLLECTOR_CHART_SHA256="$(sha256_of "$WORK_DIR/opentelemetry-collector-$OTEL_COLLECTOR_CHART_VERSION.tgz")"
step=core
# Replace only external mutations; execute the installer's real value replacement and Helm args.
helm() {
  local command=$1
  shift
  if [[ "$command" == pull ]]; then return; fi
  [[ "$command" == upgrade && "$1" == --install && "$2" == opentelemetry-collector ]] ||
    die 'unexpected Helm operation in installer fixture'
  shift 3
  local -a values=()
  while (($#)); do
    case "$1" in
      --values|--set-string) values+=("$1" "$2"); shift 2 ;;
      --namespace|--timeout) shift 2 ;;
      --create-namespace|--wait=watcher|--rollback-on-failure) shift ;;
      *) die "unexpected Helm argument $1" ;;
    esac
  done
  command helm template fixture "$WORK_DIR/parser" "${values[@]}" >"$WORK_DIR/$step.yaml"
}
kubectl() { cat >/dev/null; }
pull_chart() { printf '%s' "$WORK_DIR/opentelemetry-collector-$OTEL_COLLECTOR_CHART_VERSION.tgz"; }
install_otel_collector "$OTEL_CLIENT_ID" 'InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://example.com/'
step=full
install_chart opentelemetry-collector
validate_identity() {
  # Helm adds its document/source comments; the template emits one JSON object.
  sed '/^#/d; /^---$/d' "$1" | jq -e --arg id "$OTEL_CLIENT_ID" '
    .serviceAccount.name == "opentelemetry-collector" and
    .serviceAccount.annotations["azure.workload.identity/client-id"] == $id and
    .podLabels["azure.workload.identity/use"] == "true" and
    .config.extensions.azure_auth.workload_identity.client_id == "${env:AZURE_CLIENT_ID}"
  ' >/dev/null
}
for step in core full; do
  validate_identity "$WORK_DIR/$step.yaml" || die "$step upgrade lost the Collector Workload ID"
done
step=missing-client-id
OTEL_CLIENT_ID='' install_chart opentelemetry-collector
if validate_identity "$WORK_DIR/$step.yaml"; then die 'the identity check accepted an empty full-upgrade client ID'; fi
grep -qF 'exporters: [azure_monitor, otlp_grpc/tempo, spanmetrics]' "$HERE/values/full/otel-collector.yaml"
echo 'PASS actual core/full installer arguments retain Collector identity; missing-client-ID mutation rejected'
