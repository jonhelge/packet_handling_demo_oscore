#!/usr/bin/env bash
# Build smartparcel_oscore.hex from the oscore_pocketbase PoC firmware tree.
#
# Usage:
#   OSCORE_PB_ROOT=/path/to/oscore_pocketbase ./scripts/build-firmware.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW_ROOT="${OSCORE_PB_ROOT:-$HOME/playground/oscore_pocketbase}/ai_packet_handling_demo_poc/fw"
OUT="$ROOT/firmware/smartparcel_oscore.hex"

[[ -d "$FW_ROOT/app" ]] || { echo "FW tree not found: $FW_ROOT" >&2; exit 1; }

echo "Building in $FW_ROOT ..."
(
  cd "$FW_ROOT"
  source env.sh
  west build -b thingy91x/nrf9151/ns app --pristine -- -DEXTRA_CONF_FILE=overlay-smartparcel.conf
)
cp "$FW_ROOT/build/merged.hex" "$OUT"
echo "Wrote $OUT ($(git -C "$FW_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown))"
