#!/usr/bin/env bash
# Write aiocoap client settings.json from provision API JSON (stdin or file).
#
#   ./scripts/provision-parcel.sh sim-01 | ...
#   curl ... /api/provision -d '...' | ./scripts/export-oscore-context.sh
#
# Or: ./scripts/export-oscore-context.sh provision.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/scripts/oscore-client-context/settings.json"
INPUT="${1:--}"

if [[ "$INPUT" == "-" ]]; then BODY="$(cat)"
else BODY="$(cat "$INPUT")"
fi

# aiocoap client view: sender-id_hex = device Sender ID on the wire (API recipient_id),
# recipient-id_hex = server Sender ID (API sender_id). See aiocoap/provision_via_api.py.
jq -n \
  --arg secret "$(echo "$BODY" | jq -r .master_secret)" \
  --arg salt "$(echo "$BODY" | jq -r .master_salt)" \
  --arg api_sender "$(echo "$BODY" | jq -r .sender_id)" \
  --arg api_recipient "$(echo "$BODY" | jq -r .recipient_id)" \
  '{
    "_comment": "aiocoap OSCORE client context for sim-parcel.py",
    "sender-id_hex": $api_recipient,
    "recipient-id_hex": $api_sender,
    "secret_hex": $secret,
    "salt_hex": $salt
  }' > "$OUT"
rm -f "$ROOT/scripts/oscore-client-context/sequence.json"
echo "Wrote $OUT (reset sequence.json)"
