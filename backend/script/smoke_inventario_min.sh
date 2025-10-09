#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
API_BASE="${API_BASE:-http://127.0.0.1:3000}"
API="${API_BASE%/}/v1"
API_KEY="${KEY:-superdev}"
TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"

# Construir body con el MAT_ID real
BODY="$(jq -n --argjson mid "$MAT_ID" '{materialId:$mid, cantidad:1}')"

# Curl timeouts para evitar cuelgues
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-1}"
CURL_MAX_TIME="${CURL_MAX_TIME:-2}"
# para llamadas “normales” (fail on >=400)
curl_flags_fail=(-fsSL --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}")
# para /health mostrado en pantalla (no usar -f para que no escupa error feo)
curl_flags_nofail=(-sS --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}")

say() { echo -e "$@"; }

# ===== Helpers =====
api_get() {
  curl "${curl_flags_fail[@]}" -H "x-api-key: ${API_KEY}" "$1"
}
api_post_json() {
  local url="$1"; local data="$2"
  curl -sS --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" \
    -w '\n%{http_code}' -X POST "$url" \
    -H "x-api-key: ${API_KEY}" -H "content-type: application/json" \
    --data "$data"
}
health_ok() {
  # Devuelve 0 si /health responde 200 (ruta sin /v1)
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "${curl_flags_nofail[@]}" "${API_BASE%/}/health" || true)"
  [[ "$code" == "200" ]]
}
get_stock_for_mat() {
  # Normaliza y convierte "4.00" -> 4 (int)
  api_get "$API/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --argjson mid "$MAT_ID" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
          | ((.cantidad // 0) | tostring | tonumber? // 0 | floor)
        ][0] // 0
      '
}

# ===== Smoke =====
say "=== 🧪 Smoke Inventario (mínimo, vía API) ==="
say "⏳ Esperando API en ${API_BASE} (timeouts: connect=${CURL_CONNECT_TIMEOUT}s, max=${CURL_MAX_TIME}s)…"

ready="false"
for i in {1..60}; do
  if health_ok; then ready="true"; break; fi
  sleep 1
done
if [[ "$ready" != "true" ]]; then
  say "❌ API no respondió /health en tiempo. Revisa que el contenedor 'api' esté arriba."
  exit 1
fi

# Mostrar estado de /health “bonito” (sin -f y sin /v1)
curl "${curl_flags_nofail[@]}" "${API_BASE%/}/health" \
  | jq -r '(.ok // .status // "unknown") | if . == true then "ok" elif . == false then "fail" else . end' || true

say "🔎 Stock técnico ${TECNICO_ID} (antes)"
before="$(get_stock_for_mat)"; say "  materialId=${MAT_ID} => ${before}"

say "➕ Agregar 1 (mat ${MAT_ID})"
add_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/agregar" "$BODY")"
add_body="$(echo "$add_res" | sed -n '1,$p' | sed '$d')"
add_code="$(echo "$add_res" | tail -n 1)"
if [[ "$add_code" != "200" && "$add_code" != "201" && "$add_code" != "204" ]]; then
  say "❌ agregar falló (HTTP $add_code). Respuesta:"; echo "$add_body" | jq . || echo "$add_body"; exit 1
fi
echo "$add_body" | jq . || true

say "🔎 Stock (después de agregar)"
after_add="$(get_stock_for_mat)"; say "  => ${after_add}"

say "➖ Descontar 1 (mat ${MAT_ID})"
desc_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/descontar" "$BODY")"
desc_body="$(echo "$desc_res" | sed -n '1,$p' | sed '$d')"
desc_code="$(echo "$desc_res" | tail -n 1)"
if [[ "$desc_code" != "200" && "$desc_code" != "201" && "$desc_code" != "204" ]]; then
  say "❌ descontar falló (HTTP $desc_code). Respuesta:"; echo "$desc_body" | jq . || echo "$desc_body"; exit 1
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
