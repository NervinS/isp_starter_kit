#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"

TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  curl -fsSL -X "${method}" \
    -H "x-api-key: ${KEY}" \
    -H "Content-Type: application/json" \
    "${url}" "$@"
}
curl_get() {
  local url="$1"
  curl -fsSL -H "x-api-key: ${KEY}" "${url}"
}

echo "=== 🛠️  Smoke Técnicos (mínimo) ==="
echo "⏳ Esperando API (probando /v1/health y /health sobre ${API_BASE}) ..."
if curl_get "${API_BASE}/v1/health" >/dev/null 2>&1 || curl_get "${API_BASE}/health" >/dev/null 2>&1; then
  echo "✅ API OK en ${API_BASE}/v1/health"
else
  echo "❌ API no responde" >&2
  exit 1
fi

echo "== Smoke 1: baseline (por API) =="
stock0=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
  | jq -r --argjson mid "${MAT_ID}" '
      [ .[]
        | select((.material_id == $mid) or (.materialId == $mid))
        | .cantidad
      ][0] // 0
    ' || echo "0")
echo "stock0=${stock0}"

if [[ "${stock0}" -lt 1 ]]; then
  echo "ℹ️  Stock < 1. Agregando 1 unidad vía API (endpoint por técnico)…"
  add_1_res=$(curl_json POST "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 1}" || true)
  echo "add_1_res=${add_1_res}"
fi

stock1=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
  | jq -r --argjson mid "${MAT_ID}" '
      [ .[]
        | select((.material_id == $mid) or (.materialId == $mid))
        | .cantidad
      ][0] // 0
    ' || echo "0")
echo "stock1=${stock1} (debería ser >= 1)"

if [[ "${stock1}" -lt 1 ]]; then
  echo "ℹ️  Reintento: agregando 2 unidades…"
  add_2_res=$(curl_json POST "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 2}" || true)
  echo "add_2_res=${add_2_res}"
  stock1=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --argjson mid "${MAT_ID}" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
          | .cantidad
        ][0] // 0
      ' || echo "0")
  echo "stock1_retry=${stock1}"
fi

if [[ "${stock1}" -lt 1 ]]; then
  echo "❌ No se pudo garantizar stock >=1. Diagnóstico (por API):"
  echo "── Últimos 5 movimientos kardex para mat=${MAT_ID}"
  curl_get "${API_BASE}/v1/inventario/kardex" \
    | jq --argjson mid "${MAT_ID}" '
        [ .[]
          | select((.material_id == $mid) or (.materialId == $mid))
        ]
        | sort_by(.fecha) | reverse | .[:5]
      ' || true
  exit 1
fi

echo "🎉 Smoke Técnicos mínimo OK"
