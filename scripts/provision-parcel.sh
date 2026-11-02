#!/usr/bin/env bash
# Provision a parcel device on oscore-server and print shell commands for the Thingy.
#
#   OSCORE_URL=http://localhost:8090 OSCORE_EMAIL=... OSCORE_PASSWORD=... \
#     ./scripts/provision-parcel.sh parcel-01 "Demo parcel"
#
# Optional 4th arg: server IPv4 for `smartparcel server` (defaults to SERVER_IPV4 env).
set -eu

if [ $# -lt 1 ]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

HW_ID=$1
NAME=${2:-$HW_ID}
TRANSPORT=${3:-tn}
SERVER_IP=${4:-${SERVER_IPV4:-}}
URL=${OSCORE_URL:-http://localhost:8090}
URL=${URL%/}

command -v jq >/dev/null || { echo "provision-parcel: jq required" >&2; exit 1; }

api() {
  if [ $# -ge 3 ]; then
    curl -fsS -X "$1" "$URL$2" -H "Authorization: $TOKEN" -H 'Content-Type: application/json' -d "$3"
  else
    curl -fsS -X "$1" "$URL$2" -H "Authorization: $TOKEN"
  fi
}

TOKEN=${OSCORE_TOKEN:-}
if [ -z "$TOKEN" ]; then
  : "${OSCORE_EMAIL:?set OSCORE_EMAIL and OSCORE_PASSWORD, or OSCORE_TOKEN}"
  : "${OSCORE_PASSWORD:?set OSCORE_PASSWORD}"
  TOKEN=$(curl -fsS -X POST "$URL/api/collections/_superusers/auth-with-password" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg i "$OSCORE_EMAIL" --arg p "$OSCORE_PASSWORD" '{identity:$i,password:$p}')" | jq -r .token)
fi

MATERIAL=$(api POST /api/provision "$(jq -nc --arg h "$HW_ID" --arg t "$TRANSPORT" '{hw_id:$h,transport:$t}')")

PROFILE_ID=$(api GET "/api/collections/device_profiles/records?filter=$(jq -rn --arg f "name='smartparcel'" '$f|@uri')&perPage=1" | jq -r '.items[0].id // empty')
[ -n "$PROFILE_ID" ] || { echo "provision-parcel: no smartparcel profile — is pb_migrations mounted?" >&2; exit 1; }

DEVICE_ID=$(api GET "/api/collections/devices/records?filter=$(jq -rn --arg f "hw_id='$HW_ID'" '$f|@uri')&perPage=1" | jq -r '.items[0].id')
TAGS=$(jq -nc --arg n "$NAME" '{parcel_name:$n}')
api PATCH "/api/collections/devices/records/$DEVICE_ID" \
  "$(jq -nc --arg p "$PROFILE_ID" --argjson t "$TAGS" '{profile:$p, tags:$t}')" >/dev/null

echo "Provisioned '$NAME' ($HW_ID, device $DEVICE_ID)."
echo
echo "On the Thingy:91 X serial shell, then reboot:"
echo "$MATERIAL" | jq -r '"  oscore provision \(.master_secret) \(.master_salt) \(.recipient_id) \(.sender_id)"'
if [ -n "$SERVER_IP" ]; then
  echo "  smartparcel server $SERVER_IP"
else
  echo "  smartparcel server <your-server-ipv4>   # Fly: fly ips list --app \$FLY_APP"
fi
echo
echo "Clear terminal scrollback after copying secrets."
