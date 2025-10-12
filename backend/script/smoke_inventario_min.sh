#!/usr/bin/env bash
set -euo pipefail

# ===== Reqs rápidos =====
for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ falta $bin"; exit 1; }
done

# ===== Config =====
API_BASE="${API_BASE:-http://127.0.0.1:3000}"
API="${API_BASE%/}/v1"
API_KEY="${KEY:-superdev}"

# Para el smoke de stock técnico:
TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"

# Para el stress de /inventario/transferir:
FROM_ALMACEN_ID="${FROM_ALMACEN_ID:-9191e7cb-de60-4e29-917f-f4f005963863}" # CENTRAL
TO_ALMACEN_ID="${TO_ALMACEN_ID:-62ebd37f-44c4-499d-b9ed-7bee75b09275}"     # TEC-6

# Curl timeouts
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-1}"
CURL_MAX_TIME="${CURL_MAX_TIME:-2}"

curl_flags_fail=(-fsSL --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}")
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
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "${curl_flags_nofail[@]}" "${API_BASE%/}/health" || true)"
  [[ "$code" == "200" ]]
}
get_stock_for_mat() {
  api_get "$API/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --argjson mid "$MAT_ID" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
          | ((.cantidad // 0) | tostring | tonumber? // 0 | floor)
        ][0] // 0
      '
}

# ===== Inicio =====
say "=== 🧪 Smoke Inventario (mínimo, vía API) ==="
say "⏳ Esperando API en ${API_BASE} (timeouts: connect=${CURL_CONNECT_TIMEOUT}s, max=${CURL_MAX_TIME}s)…"

ready="false"
for _ in {1..60}; do
  if health_ok; then ready="true"; break; fi
  sleep 1
done
if [[ "$ready" != "true" ]]; then
  say "❌ API no respondió /health en tiempo."
  exit 1
fi

# Mostrar /health "bonito"
curl "${curl_flags_nofail[@]}" "${API_BASE%/}/health" \
  | jq -r '(.ok // .status // "unknown") | if . == true then "ok" elif . == false then "fail" else . end' || true

# ===== Caso feliz agregar/descontar =====
say "🔎 Stock técnico ${TECNICO_ID} (antes)"
before="$(get_stock_for_mat)"; say "  materialId=${MAT_ID} => ${before}"

BODY="$(jq -n --argjson mid "$MAT_ID" '{materialId:$mid, cantidad:1}')"

say "➕ Agregar 1 (mat ${MAT_ID})"
add_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/agregar" "$BODY")"
add_body="$(echo "$add_res" | sed -n '1,$p' | sed '$d')"
add_code="$(echo "$add_res" | tail -n 1)"
if [[ "$add_code" != "200" && "$add_code" != "201" && "$add_code" != "204" ]]; then
  say "❌ agregar falló (HTTP $add_code)"; echo "$add_body" | jq . || echo "$add_body"; exit 1
fi
echo "$add_body" | jq . || true

say "🔎 Stock (después de agregar)"
after_add="$(get_stock_for_mat)"; say "  => ${after_add}"

say "➖ Descontar 1 (mat ${MAT_ID})"
desc_res="$(api_post_json "$API/inventario/tecnicos/${TECNICO_ID}/descontar" "$BODY")"
desc_body="$(echo "$desc_res" | sed -n '1,$p' | sed '$d')"
desc_code="$(echo "$desc_res" | tail -n 1)"
if [[ "$desc_code" != "200" && "$desc_code" != "201" && "$desc_code" != "204" ]]; then
  say "❌ descontar falló (HTTP $desc_code)"; echo "$desc_body" | jq . || echo "$desc_body"; exit 1
fi
echo "$desc_body" | jq . || true

say "🔎 Stock (después de descontar)"
after_desc="$(get_stock_for_mat)"; say "  => ${after_desc}"

if [[ "$after_desc" == "$before" ]]; then
  say "🎉 OK: stock volvió a su valor original (${before})."
else
  say "⚠️  Stock final (${after_desc}) difiere del inicial (${before})."
  exit 2
fi

# ===== Verificación idempotencia (header + body) =====
say "🔁 Verificando Idempotency-Replayed + _idempotent en /inventario/transferir"
IDEM_KEY="idem-smoke-hdr-$$-$RANDOM"
FIRST_PAYLOAD="$(jq -n \
  --argjson mid "$MAT_ID" \
  --argjson qty 1 \
  --arg from "$FROM_ALMACEN_ID" \
  --arg to "$TO_ALMACEN_ID" \
  --arg key "$IDEM_KEY" \
  '{materialId:$mid,cantidad:$qty,fromAlmacenId:$from,toAlmacenId:$to,idempotencyKey:$key}')"

first="$(curl -sS -i -X POST "$API/inventario/transferir" \
  -H "x-api-key: ${API_KEY}" -H "content-type: application/json" \
  --data-raw "$FIRST_PAYLOAD")"
echo "$first" | grep -i '^Idempotency-Replayed:' >/dev/null && { echo "❌ no debería venir en first"; exit 3; } || echo "✅ sin header en first"

retry="$(curl -sS -i -X POST "$API/inventario/transferir" \
  -H "x-api-key: ${API_KEY}" -H "content-type: application/json" \
  --data-raw "$FIRST_PAYLOAD")"
echo "$retry" | grep -i '^Idempotency-Replayed:' >/dev/null && echo "✅ header en retry" || { echo "❌ faltó header en retry"; exit 3; }
echo "$retry" | tail -n1 | jq '._idempotent' | grep -q true && echo "✅ _idempotent:true en retry" || { echo "❌ body sin _idempotent:true"; exit 3; }

# ===== Stress paralelo opcional =====
if [[ "${RUN_STRESS:-0}" != "0" ]]; then
  say "🏎️  Stress paralelo (5x misma key) verificando headers"
  KEY="idem-stress-hdr-$$-$RANDOM"
  export API API_KEY KEY
  STRESS_PAYLOAD=$(jq -nc \
    --argjson mid "$MAT_ID" \
    --argjson qty 2 \
    --arg from "$FROM_ALMACEN_ID" \
    --arg to "$TO_ALMACEN_ID" \
    --arg key "$KEY" \
    '{materialId:$mid,cantidad:$qty,fromAlmacenId:$from,toAlmacenId:$to,idempotencyKey:$key}')
  export STRESS_PAYLOAD

  seq 1 5 | xargs -I{} -P5 bash -lc '
    curl -sS -D - -o /dev/null -X POST "$API/inventario/transferir" \
      -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
      --data-raw "$STRESS_PAYLOAD" \
    | awk "BEGIN{IGNORECASE=1} /^Idempotency-Replayed:/{print \"idempotency-replayed: true\"; got=1} END{if(!got) print \"(no header)\"}"
  ' | sort | uniq -c

  echo
  echo "👉 Tip: con una key nueva, lo esperado es ~1 '(no header)' y el resto 'idempotency-replayed: true'."
  echo "    Si ves 5 con header, probablemente reutilizaste una key ya usada anteriormente."
fi

echo "✅ Smoke inventario OK."
