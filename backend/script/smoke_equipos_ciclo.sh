#!/usr/bin/env bash
# script/smoke_equipos_ciclo.sh
# Ciclo completo: asegurar ONU en almacén -> entregar a técnico -> chequear stock -> devolver -> chequear stock
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

stock_count_alm() {
  curl_json GET "${API}/equipos/stock?almacen=${ALM}" | jq '[.[] | select(.tipo=="ONU")] | length'
}

stock_count_tec() {
  curl_json GET "${API}/equipos/stock?tecnicoId=${TEC_ID}" | jq '[.[] | select(.tipo=="ONU")] | length'
}

say "== equipos: ciclo completo (ONU) =="

# 0) baseline
c_alm_before="$(stock_count_alm)"
c_tec_before="$(stock_count_tec)"
say "Baseline: ALM=${ALM} ONU=${c_alm_before} | TEC-${TEC_ID} ONU=${c_tec_before}"

# 1) asegurar ONU en ALMACÉN; si no hay, reciclar una desde algún técnico
eid="$(curl_json GET "${API}/equipos/stock?almacen=${ALM}" | jq -r '[.[] | select(.tipo=="ONU")] | .[0].id // empty')"
if [[ -z "${eid}" ]]; then
  say "No hay ONU en ${ALM}; reciclando 1 desde un técnico…"
  # tomar una desde TEC-6 (o el primero que tenga)
  tid="${TEC_ID}"
  eid_from_tec="$(curl_json GET "${API}/equipos/stock?tecnicoId=${tid}" | jq -r '[.[] | select(.tipo=="ONU")] | .[0].id // empty')"
  if [[ -n "${eid_from_tec}" ]]; then
    curl_json POST "${API}/equipos/devolver" "$(jq -n --arg id "$eid_from_tec" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')" >/dev/null
    eid="${eid_from_tec}"
  else
    say "No hay ONU para reciclar. OK (no se puede ejecutar ciclo completo)."
    exit 0
  fi
fi
say "Preparado equipo id=${eid} en ${ALM}"

# 2) ENTREGAR a TEC-6
r1="$(curl_json POST "${API}/equipos/entregar" "$(jq -n --arg id "$eid" --argjson tec "${TEC_ID}" --arg alm "${ALM}" '{id:$id, tecnicoId:$tec, fromAlmacen:$alm}')" )"
echo "${r1}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'
# retry idempotente
r1b="$(curl_json POST "${API}/equipos/entregar" "$(jq -n --arg id "$eid" --argjson tec "${TEC_ID}" --arg alm "${ALM}" '{id:$id, tecnicoId:$tec, fromAlmacen:$alm}')" )"
echo "${r1b}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'

# 3) verificar stock después de ENTREGAR
c_alm_mid="$(stock_count_alm)"
c_tec_mid="$(stock_count_tec)"
say "Post-entrega: ALM=${ALM} ONU=${c_alm_mid} | TEC-${TEC_ID} ONU=${c_tec_mid}"

# 4) DEVOLVER al ALMACÉN
r2="$(curl_json POST "${API}/equipos/devolver" "$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')" )"
echo "${r2}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'
# retry idempotente
r2b="$(curl_json POST "${API}/equipos/devolver" "$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')" )"
echo "${r2b}" | jq '{ok, _idempotent, from: (if .from then .from.id else null end), to_len: (.to|length)}'

# 5) verificar stock final
c_alm_after="$(stock_count_alm)"
c_tec_after="$(stock_count_tec)"
say "Post-devolución: ALM=${ALM} ONU=${c_alm_after} | TEC-${TEC_ID} ONU=${c_tec_after}"

say "OK ciclo completo."
