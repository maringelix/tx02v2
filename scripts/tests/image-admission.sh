#!/usr/bin/env bash
# Parse the rendered policy structurally; runtime signature verification is a separate cloud proof.
set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cmd helm jq
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT
mkdir -p "$WORK/chart/templates"
cat >"$WORK/chart/Chart.yaml" <<'YAML'
apiVersion: v2
name: image-policy-fixture
version: 0.1.0
YAML
cat >"$WORK/chart/templates/policy.yaml" <<'TPL'
{{ .Files.Get "policy.yaml" | fromYaml | toJson }}
TPL
validate() {
  cp "$1" "$WORK/chart/policy.yaml"
  helm template fixture "$WORK/chart" | sed '/^#/d; /^---$/d' | jq -e '
    .kind == "ImageValidatingPolicy" and
    .spec.evaluation.mode == "Kubernetes" and
    .spec.evaluation.background.enabled == false and
    .spec.failurePolicy == "Fail" and .spec.validationActions == ["Deny"] and
    .spec.matchConstraints.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "dx02v2" and
    .spec.matchConstraints.resourceRules[0].resources == ["pods"] and
    .spec.matchConstraints.resourceRules[0].operations == ["CREATE", "UPDATE"] and
    .spec.matchImageReferences == [{"glob":"*.azurecr.io/dx02v2/api@sha256:*"},{"glob":"*.azurecr.io/dx02v2/web@sha256:*"}] and
    .spec.validationConfigurations.required == true and .spec.validationConfigurations.verifyDigest == true and
    .spec.credentials.providers == ["azure"] and
    .spec.attestors[0].cosign.keyless.identities == [{"subject":"https://github.com/example-owner/dx02v2/.github/workflows/deploy-azure.yml@refs/heads/main","issuer":"https://token.actions.githubusercontent.com"}] and
    .spec.attestations[0].intoto.type == "https://github.com/maringelix/tx00v2/attestations/promoted-image/v1" and
    (.spec.validations[0].expression | contains("verifyAttestationSignatures"))
  ' >/dev/null
}
bash "$REPO_ROOT/platform/render-manifests.sh" https://tx02v2-lab-00000000.vault.azure.net/ \
  00000000-0000-0000-0000-000000000000 --full example-owner \
  --acr-login-server tx02v2lab00000000.azurecr.io --agc-subnet-cidr 10.20.4.0/24 \
  --only full/image-verification.yaml >"$WORK/policy.yaml"
validate "$WORK/policy.yaml" || die 'rendered policy is not a fail-closed Kubernetes admission policy'
sed 's/mode: Kubernetes/mode: JSON/' "$WORK/policy.yaml" >"$WORK/json-mode.yaml"
if validate "$WORK/json-mode.yaml"; then die 'the Kubernetes policy check accepted JSON mode'; fi
sed 's/- Deny/- Audit/' "$WORK/policy.yaml" >"$WORK/audit-only.yaml"
if validate "$WORK/audit-only.yaml"; then die 'the Kubernetes policy check accepted audit-only admission'; fi
sed 's|github.com/example-owner/dx02v2|github.com/another-owner/dx02v2|' "$WORK/policy.yaml" >"$WORK/foreign-signer.yaml"
if validate "$WORK/foreign-signer.yaml"; then die 'the Kubernetes policy check accepted a foreign signer'; fi
echo 'PASS parsed Kubernetes policy and registry constraints; JSON/audit/foreign-signer mutants rejected'
