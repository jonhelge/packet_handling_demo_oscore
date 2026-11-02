# Shared helpers for scripts/*.sh — sourced, not executed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    export "$key=$value"
  done < "$ENV_FILE"
fi

die() { echo "error: $*" >&2; exit 1; }

need() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || die "'$cmd' is required but not installed"
  done
}

need curl jq

default_base_url() {
  if [[ -n "${PUBLIC_URL:-}" ]]; then echo "${PUBLIC_URL%/}"
  elif [[ -n "${FLY_APP:-}" ]]; then echo "https://$FLY_APP.fly.dev"
  else echo "http://localhost:8090"; fi
}

set_env() {
  touch "$ENV_FILE"
  if grep -q "^$1=" "$ENV_FILE"; then
    local tmp; tmp="$(mktemp)"
    awk -v k="$1" -v v="$2" 'BEGIN{FS=OFS="="} $1==k{print k "=" v; next} {print}' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    echo "$1=$2" >> "$ENV_FILE"
  fi
  export "$1=$2"
}
