#!/usr/bin/env bash
set -euo pipefail

# Config
API_BASE="${API_BASE:-http://127.0.0.1:3000}"
API="${API_BASE%/}/v1"
API_KEY="${KEY:-superdev}"
TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"
BODY='{"materialId":3,"cantidad":1}'

say() { echo -e "$@"; }

# Helpers
api_get() {
  curl -fsSL -H "x-api-key: ${API_KEY}" "$1"
}
api_post_json() {
  local url="$1"
  local data="$2"
  curl -sS -w '\n%{http_code}' -X POST "$url" \
    -H "x-api-key: ${API_KEY}" \
    -H "content-type: application/json" \
    --data "$data"
}
get_stock_for_mat() {
  # Acepta material_id y materialId; si no está, 0
  api_get "$API/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --argjson mid "$MAT_ID" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
          | .cantidad
        ][0] // 0
      '
}

# Smoke
say "=== 🧪 Smoke Inventario (mínimo, vía API) ==="

say "⏳ Esperando API en ${API_BASE}…"
for i in {1..60}; do
  if curl -sf -H "x-api-key: ${API_KEY}" "${API}/health" >/dev/null; then
    break
  fi
  sleep 1
done
api_get "${API}/health" | jq -r '(.ok // .status // "unknown") | if . == true then "ok" elif . == false then "fail" else . end' || true

say "🔎 Stock técnico ${TECNICO_ID} (antes)"
before="$(get_stock_for_mat)"; say "  materialId=${MAT_ID} => ${before}"

say "➕ Agregar 1 (mat ${MAT_ID})"
add_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/agregar" "$BODY")"
add_body="$(echo "$add_res" | head -n -1)"
add_code="$(echo "$add_res" | tail -n 1)"
if [[ "$add_code" != "200" && "$add_code" != "201" && "$add_code" != "204" ]]; then
  say "❌ agregar falló (HTTP $add_code). Respuesta:"
  echo "$add_body" | jq . || echo "$add_body"
  exit 1
fi
echo "$add_body" | jq . || true

say "🔎 Stock (después de agregar)"
after_add="$(get_stock_for_mat)"; say "  => ${after_add}"

say "➖ Descontar 1 (mat ${MAT_ID})"
desc_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/descontar" "$BODY")"
desc_body="$(echo "$desc_res" | head -n -1)"
desc_code="$(echo "$desc_res" | tail -n 1)"
if [[ "$desc_code" != "200" && "$desc_code" != "201" && "$desc_code" != "204" ]]; then
  say "❌ descontar falló (HTTP $desc_code). Respuesta:"
  echo "$desc_body" | jq . || echo "$desc_body"
  exit 1
fi
echo "$desc_body" | jq . || true

say "🔎 Stock (después de descontar)"
after_desc="$(get_stock_for_mat)"; say "  => ${after_desc}"

if [[ "$after_desc" == "$before" ]]; then
  say "🎉 OK: stock volvió a su valor original (${before})."
  exit 0
else
  say "⚠️  Stock final (${after_desc}) difiere del inicial (${before})."
  exit 2
fi
