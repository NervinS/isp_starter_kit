#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:3000}"
KEY="${KEY:-superdev}"
TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"

CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-1}"
CURL_MAX_TIME="${CURL_MAX_TIME:-2}"

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  curl -fsSL -X "${method}" \
    --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" \
    -H "x-api-key: ${KEY}" \
    -H "Content-Type: application/json" \
    "${url}" "$@"
}
curl_get() {
  local url="$1"
  curl -fsSL \
    --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" \
    -H "x-api-key: ${KEY}" "${url}"
}

echo "=== 🛠️  Smoke Técnicos (mínimo) ==="
echo "⏳ Esperando API (GET /health) …"
ready="false"
for i in {1..60}; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" "${API_BASE%/}/health" || true)"
  if [[ "$code" == "200" ]]; then ready="true"; break; fi
  sleep 1
done
[[ "$ready" == "true" ]] || { echo "❌ API no responde /health"; exit 1; }
echo "✅ API OK"

echo "== Smoke 1: baseline (por API) =="
stock0=$(curl_get "${API_BASE%/}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
  | jq -r --argjson mid "${MAT_ID}" '
      [ .[]
        | select((.material_id == $mid) or (.materialId == $mid))
        | ((.cantidad // 0) | tostring | tonumber? // 0 | floor)
      ][0] // 0
    ' || echo "0")
echo "stock0=${stock0}"

if [[ "${stock0}" -lt 1 ]]; then
  echo "ℹ️  Stock < 1. Agregando 1 unidad vía API (endpoint por técnico)…"
  add_1_res=$(curl_json POST "${API_BASE%/}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 1}" || true)
  echo "add_1_res=${add_1_res}"
fi

stock1=$(curl_get "${API_BASE%/}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
  | jq -r --argjson mid "${MAT_ID}" '
      [ .[]
        | select((.material_id == $mid) or (.materialId == $mid))
        | ((.cantidad // 0) | tostring | tonumber? // 0 | floor)
      ][0] // 0
    ' || echo "0")
echo "stock1=${stock1} (debería ser >= 1)"

if [[ "${stock1}" -lt 1 ]]; then
  echo "ℹ️  Reintento: agregando 2 unidades…"
  add_2_res=$(curl_json POST "${API_BASE%/}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 2}" || true)
  echo "add_2_res=${add_2_res}"
  stock1=$(curl_get "${API_BASE%/}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --argjson mid "${MAT_ID}" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
          | ((.cantidad // 0) | tostring | tonumber? // 0 | floor)
        ][0] // 0
      ' || echo "0")
  echo "stock1_retry=${stock1}"
fi

if [[ "${stock1}" -lt 1 ]]; then
  echo "❌ No se pudo garantizar stock >=1. Diagnóstico (por API):"
  echo "── Últimos 5 movimientos kardex para mat=${MAT_ID}"
  curl_get "${API_BASE%/}/v1/inventario/kardex" \
    | jq --argjson mid "${MAT_ID}" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
        ]
        | sort_by(.fecha) | reverse | .[:5]
      ' || true
  exit 1
fi

echo "🎉 Smoke Técnicos mínimo OK"
