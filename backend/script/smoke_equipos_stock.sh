#!/usr/bin/env bash
# script/smoke_equipos_stock.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"
ALM="${ALM:-ALM-PRINC}"
TEC_ID="${TEC_ID:-6}"

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1-}"
  if [[ -n "${data}" ]]; then
    curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" -X "${method}" -d "${data}" "${url}"
  else
    curl -sfS -H "x-api-key: ${KEY}" -X "${method}" "${url}"
  fi
}

echo "== equipos: stock por almacén (${ALM}) =="
alm="$(curl_json GET "${API}/equipos/stock?almacen=${ALM}")"
echo "total=$(jq 'length' <<<"$alm")"
jq '.[0]' <<<"$alm" || true

echo
echo "== equipos: stock por técnico (TEC-${TEC_ID}) =="
tec="$(curl_json GET "${API}/equipos/stock?tecnicoId=${TEC_ID}")"
echo "total=$(jq 'length' <<<"$tec")"
jq '.[0]' <<<"$tec" || true
