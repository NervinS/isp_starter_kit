#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"

echo "== equipos/historial por SN y MAC =="

pick_any() {
  local tipo="$1"
  curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=${tipo}" | jq -c '.items[0]'
}

row="$(pick_any ONU)"
if [[ -z "${row}" || "${row}" == "null" ]]; then
  row="$(pick_any REPETIDOR)"
fi

if [[ -z "${row}" || "${row}" == "null" ]]; then
  echo "No fue posible encontrar un equipo disponible; prueba manual:"
  echo "  curl -s -H 'x-api-key: $KEY' \"$API/v1/equipos/disponibles?tipo=ONU\" | jq ."
  exit 0
fi

sn="$(jq -r '.sn' <<<"$row")"
mac="$(jq -r '.mac' <<<"$row")"

echo "-- por SN = $sn"
curl -s -H "x-api-key: $KEY" "$API/v1/equipos/historial?sn=$sn" \
  | jq '{equipo, historial_len: (.historial|length)}'

echo "-- por MAC = $mac"
curl -s -H "x-api-key: $KEY" "$API/v1/equipos/historial?mac=$mac" \
  | jq '{equipo, historial_len: (.historial|length)}'

echo "OK historial."
