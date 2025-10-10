#!/usr/bin/env bash
# script/smoke_equipos_devolver.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"
ALM="${ALM:-ALM-PRINC}"
TEC_ID="${TEC_ID:-6}"

say(){ echo -e "$@"; }

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

say "== equipos: devolver (tipo=ONU) =="

# 1) intenta encontrar ONU en TEC-6
eid="$(curl_json GET "${API}/equipos/stock?tecnicoId=${TEC_ID}" | jq -r '[.[] | select(.tipo=="ONU")] | .[0].id // empty')"

# 2) si no hay, intenta traer una del ALMACÉN → primero entregar a TEC-6
if [[ -z "${eid}" ]]; then
  say "TEC-${TEC_ID} no tiene ONU; intentando traer una del almacén ${ALM}…"
  eid="$(curl_json GET "${API}/equipos/stock?almacen=${ALM}" | jq -r '[.[] | select(.tipo=="ONU")] | .[0].id // empty')"
  if [[ -n "${eid}" ]]; then
    say "Entregando ${eid} a TEC-${TEC_ID} para poder devolverla…"
    curl_json POST "${API}/equipos/entregar" "$(jq -n --arg id "$eid" --argjson tec "${TEC_ID}" --arg alm "${ALM}" '{id:$id, tecnicoId:$tec, fromAlmacen:$alm}')" >/dev/null
  fi
fi

# 3) volver a chequear en TEC-6
if [[ -z "${eid}" ]]; then
  say "No hay ONU disponible para devolver (ni en TEC-${TEC_ID} ni en ${ALM}). OK (nada que hacer)."
  exit 0
fi

say "Usando equipo id=${eid} para devolver a ${ALM}"

# 4) devolver
resp1="$(curl_json POST "${API}/equipos/devolver" "$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')" )"
echo "${resp1}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'

# 5) idempotencia (retry)
resp2="$(curl_json POST "${API}/equipos/devolver" "$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')" )"
echo "${resp2}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'
