#!/usr/bin/env bash
# Insert demo classification rows (superuser REST) — no device or OSCORE needed.
#
#   scripts/send-test.sh Carrying 0.92
#   scripts/send-test.sh --demo
set -euo pipefail
source "$(dirname "$0")/lib.sh"

URL="$(default_base_url)"
DEMO=0
STATE="carrying"
CONF="0.92"
DEVICE="${TEST_HW_ID:-demo-parcel-01}"
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) URL="${2%/}"; shift 2 ;;
    -d) DEVICE="$2"; shift 2 ;;
    --demo) DEMO=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

map_state() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    idle) echo idle ;;
    shaking) echo shaking ;;
    impact) echo impact ;;
    "free fall"|freefall) echo freefall ;;
    carrying) echo carrying ;;
    "in car"|car) echo car ;;
    placed) echo placed ;;
    *) echo "$1" ;;
  esac
}

CLASS_IDX() {
  case "$1" in
    idle) echo 0 ;; shaking) echo 1 ;; impact) echo 2 ;; freefall) echo 3 ;;
    carrying) echo 4 ;; car) echo 5 ;; placed) echo 6 ;;
    *) echo 0 ;;
  esac
}

auth_token() {
  if [[ -n "${OSCORE_TOKEN:-}" ]]; then echo "$OSCORE_TOKEN"; return; fi
  local email="${OSCORE_EMAIL:-${PB_ADMIN_EMAIL:-}}"
  : "${email:?set OSCORE_EMAIL or PB_ADMIN_EMAIL, or OSCORE_TOKEN}"
  : "${PB_ADMIN_PASSWORD:?set PB_ADMIN_PASSWORD (or OSCORE_PASSWORD)}"
  local pass="${OSCORE_PASSWORD:-$PB_ADMIN_PASSWORD}"
  curl -fsS -X POST "$URL/api/collections/_superusers/auth-with-password" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg i "$email" --arg p "$pass" '{identity:$i,password:$p}')" | jq -r .token
}

insert_one() {
  local dev="$1" label="$2" conf="$3"
  local state idx now_ms probs
  state="$(map_state "$label")"
  idx="$(CLASS_IDX "$state")"
  now_ms=$(($(date +%s)*1000))
  local body
  body=$(jq -nc \
    --arg hw "$dev" --arg st "$state" --argjson idx "$idx" --argjson conf "$conf" \
    --argjson ms "$now_ms" --argjson seq "$RANDOM" \
    '{hw_id:$hw, state:$st, class_idx:$idx, confidence:$conf, seq:$seq, server_ms:$ms,
      probabilities:{idle:0.02,shaking:0.02,impact:0.02,freefall:0.02,carrying:0.02,car:0.02,placed:0.02}}')
  body=$(echo "$body" | jq --arg st "$state" --argjson c "$conf" '.probabilities[$st]=$c')

  printf '%-18s %-10s → ' "$dev" "$state"
  curl -fsS -X POST "$URL/api/collections/classifications/records" \
    -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
    -d "$body" | jq -r '.id' | xargs -I{} echo "stored {}"
}

TOKEN="$(auth_token)"

if [[ $DEMO -eq 0 ]]; then
  [[ ${#ARGS[@]} -ge 1 ]] && STATE="${ARGS[0]}"
  [[ ${#ARGS[@]} -ge 2 ]] && CONF="$(echo "${ARGS[1]}" | awk '{if($1>1) print $1/100; else print $1}')"
  insert_one "$DEVICE" "$STATE" "$CONF"
  exit 0
fi

echo "Demo journey → $URL/ (Ctrl-C to stop)"
JOURNEY=(Idle Carrying Carrying Placed "in Car" Shaking Impact Placed Idle)
seq=0
while true; do
  for label in "${JOURNEY[@]}"; do
    seq=$((seq+1))
    insert_one "demo-parcel-A" "$label" "0.9"
    sleep 2
    insert_one "demo-parcel-B" "${JOURNEY[$((RANDOM % ${#JOURNEY[@]}))]}" "0.88"
    sleep 2
  done
done
