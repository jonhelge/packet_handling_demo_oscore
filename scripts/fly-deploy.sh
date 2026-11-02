#!/usr/bin/env bash
# Deploy SmartParcel (oscore-server + extensions) to Fly.io.
#
# Usage: scripts/fly-deploy.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need fly openssl
cd "$ROOT"

[[ -n "${FLY_APP:-}" ]] || die "set FLY_APP in .env (globally unique → https://<FLY_APP>.fly.dev)"
REGION="${FLY_REGION:-arn}"
VERSION="${OSCORE_SERVER_VERSION:-0.1.0-preview.2}"

fly auth whoami >/dev/null 2>&1 || die "not logged in — run: fly auth login"

[[ -n "${PB_OSCORE_KEK:-}" ]] || set_env PB_OSCORE_KEK "$(openssl rand -hex 32)"

if ! fly status --app "$FLY_APP" >/dev/null 2>&1; then
  echo "Creating Fly app $FLY_APP"
  if [[ -n "${FLY_ORG:-}" ]]; then fly apps create "$FLY_APP" --org "$FLY_ORG"
  else fly apps create "$FLY_APP"; fi
fi

if [[ "$(fly volumes list --app "$FLY_APP" --json | jq '[.[] | select(.name == "pb_data")] | length')" == "0" ]]; then
  echo "Creating volume pb_data in $REGION"
  fly volumes create pb_data --app "$FLY_APP" --region "$REGION" --size 1 --yes
fi

if ! fly ips list --app "$FLY_APP" --json | jq -e '.[] | select(.type == "v4" and .address != null)' >/dev/null; then
  echo "Allocating dedicated IPv4 (required for UDP CoAP from devices)"
  # --yes accepts the $2/mo charge; without it the command needs a TTY and silently skips.
  fly ips allocate-v4 --yes --app "$FLY_APP" \
    || echo "warning: IPv4 allocation failed — run: fly ips allocate-v4 --yes --app $FLY_APP" >&2
fi

fly secrets set --app "$FLY_APP" --stage \
  "PB_OSCORE_KEK=$PB_OSCORE_KEK" \
  "PGPS_DISABLE=1" >/dev/null

fly deploy --app "$FLY_APP" --primary-region "$REGION" --ha=false \
  --build-arg "OSCORE_SERVER_VERSION=$VERSION"

if [[ -n "${PB_ADMIN_EMAIL:-}" && -n "${PB_ADMIN_PASSWORD:-}" ]]; then
  fly ssh console --app "$FLY_APP" -C \
    "oscore-server superuser upsert '$PB_ADMIN_EMAIL' '$PB_ADMIN_PASSWORD' --dir=/pb_data" || true
fi

IPV4="$(fly ips list --app "$FLY_APP" --json | jq -r '[.[] | select(.type == "v4") | .address] | first // empty')"
URL="https://$FLY_APP.fly.dev"

cat <<EOF

Deployed.
  Dashboard : $URL/
  Admin UI  : $URL/_/
  CoAP/UDP  : ${IPV4:-<run: fly ips list --app $FLY_APP>}:5683

On the Thingy shell after provisioning:
  smartparcel server ${IPV4:-YOUR_SERVER_IPV4}

Next: ./scripts/provision-parcel.sh <hw_id> "My parcel"
EOF
