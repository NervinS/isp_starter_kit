#!/usr/bin/env bash
# script/smoke_equipos_stock.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"
ALM="${ALM:-ALM-PRINC}"
TEC_ID="${TEC_ID:-6}"

curl_json_status() {
  local method="$1"; shift; local url="$1"; shift; local data="${1-}"
  if [[ -n "${data}" ]]; then
    curl -sS -H "x-api-key: ${KEY}" -H "content-type: application/json" \
         -X "${method}" -d "${data}" "${url}" -w "\n%{http_code}" || true
  else
    curl -sS -H "x-api-key: ${KEY}" -X "${method}" "${url}" -w "\n%{http_code}" || true
  fi
}

echo "== equipos: stock por almacén (${ALM}) =="
resp_code="$(curl_json_status GET "${API}/equipos/stock?almacen=${ALM}")"
alm_body="$(sed '$d' <<<"${resp_code}")"
alm_code="$(tail -n1 <<<"${resp_code}")"
echo "${alm_body}"
echo "HTTP status almacén: ${alm_code}"
total_alm="$(jq -r 'if type=="array" then length
                    elif type=="object" and .items then (.items|length)
                    else 0 end' <<<"${alm_body}")"
echo "total=${total_alm}"
echo

echo "== equipos: stock por técnico (TEC-${TEC_ID}) =="
resp_code="$(curl_json_status GET "${API}/equipos/stock?tecnicoId=${TEC_ID}")"
tec_body="$(sed '$d' <<<"${resp_code}")"
tec_code="$(tail -n1 <<<"${resp_code}")"
echo "${tec_body}"
echo "HTTP status técnico: ${tec_code}"
total_tec="$(jq -r 'if type=="array" then length else 0 end' <<<"${tec_body}")"
echo "total=${total_tec}"
