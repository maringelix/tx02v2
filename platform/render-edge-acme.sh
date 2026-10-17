#!/usr/bin/env bash
# Offline renderer for the full-profile ACME bootstrap. Arguments are public contract values.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/../scripts/lib/common.sh"

(($# == 4)) || die "usage: $0 DNS_HOSTNAME ACME_EMAIL AGC_ID AGC_FRONTEND"
hostname=$1 email=$2 agc_id=$3 frontend=$4
label='[a-z0-9]([a-z0-9-]*[a-z0-9])?'
guid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
[[ "$hostname" =~ ^${label}(\.${label})+$ ]] || die "DNS_HOSTNAME is not a lowercase public hostname"
[[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "ACME_EMAIL is not a contact email"
[[ "$agc_id" =~ ^/subscriptions/${guid}/resourceGroups/tx02v2-lab/providers/Microsoft\.ServiceNetworking/trafficControllers/tx02v2-lab-agc$ ]] ||
  die "AGC_ID does not identify the AGC of tx02v2-lab"
[[ "$frontend" == tx02v2-lab-frontend ]] || die "AGC_FRONTEND does not identify the frontend of tx02v2-lab"

content="$(<"$HERE/manifests/full/edge-acme.yaml")"
content="${content//__DNS_HOSTNAME__/$hostname}"
content="${content//__ACME_EMAIL__/$email}"
content="${content//__AGC_ID__/$agc_id}"
content="${content//__AGC_FRONTEND__/$frontend}"
[[ ! "$content" =~ __[A-Z][A-Z0-9_]*__ ]] || die "unresolved placeholder in the ACME edge manifest"
printf '%s\n' "$content"
