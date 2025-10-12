#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"
ALM="${ALM:-ALM-PRINC}"
TEC_ID="${TEC_ID:-6}"

say(){ echo -e "$@"; }
curl_json() {
  local method="$1"; shift; local url="$1"; shift; local data="${1-}"
  if [[ -n "${data}" ]]; then
    curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" -X "${method}" -d "${data}" "${url}"
  else
    curl -sfS -H "x-api-key: ${KEY}" -X "${method}" "${url}"
  fi
}

say "== equipos: devolver (tipo=ONU) =="

# 1) toma un id de ONU en almacén
eid="$(curl_json GET "${API}/equipos/disponibles?tipo=ONU" \
  | jq -r '.items[]? | select(.owner_tipo=="ALMACEN" and .owner_id=="'"${ALM}"'") | .id' | head -n1)"

if [[ -z "${eid}" ]]; then
  say "No hay ONU en ${ALM}. OK (nada que hacer)."
  exit 0
fi

# 2) entrégalo al técnico para poder probar la devolución
say "Entregando ${eid} a TEC-${TEC_ID}…"
curl_json POST "${API}/equipos/entregar" \
  "$(jq -n --arg id "$eid" --argjson tec "${TEC_ID}" --arg alm "${ALM}" \
     '{id:$id, tecnicoId:$tec, fromAlmacen:$alm}')" >/dev/null

# 3) devolver al almacén (algunas versiones esperan 'destinoAlmacen', otras 'toAlmacen').
# Probamos primero 'destinoAlmacen' y si falla, reintentamos con 'toAlmacen'.
payload_dest="$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, destinoAlmacen:$alm}')"
payload_to="$(jq -n --arg id "$eid" --arg alm "${ALM}" '{id:$id, toAlmacen:$alm}')"

say "Devolviendo ${eid} a ${ALM}…"
resp="$(curl_json POST "${API}/equipos/devolver" "${payload_dest}" || true)"
if [[ -z "$resp" || "$(jq -r 'type' <<<"$resp" 2>/dev/null)" == "null" ]]; then
  resp="$(curl_json POST "${API}/equipos/devolver" "${payload_to}" || true)"
fi
echo "$resp" | jq '.' || true

# 4) validación por estado: debe quedar en ALMACEN / ALM-PRINC
check="$(curl_json GET "${API}/equipos/disponibles?tipo=ONU" \
  | jq -r --arg id "$eid" --arg alm "$ALM" \
      '[.items[]? | select(.id==$id)][0] | {id, owner_tipo, owner_id}')"

say "Post-devolución:"
echo "$check" | jq '.'

ownert="$(jq -r '.owner_tipo // ""' <<<"$check")"
ownerid="$(jq -r '.owner_id // ""' <<<"$check")"

if [[ "$ownert" == "ALMACEN" && "$ownerid" == "$ALM" ]]; then
  say "OK devolución confirmada."
else
  say "ADVERTENCIA: el equipo no quedó en ${ALM} (owner_tipo=${ownert}, owner_id=${ownerid})."
fi
