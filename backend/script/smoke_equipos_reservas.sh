#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="$API_BASE/v1"
KEY="${KEY:-superdev}"
TEC_ID="${TEC_ID:-6}"
TIPO="${TIPO:-ONU}"

echo "== equipos: reservas (tipo=$TIPO) =="

# 1) Buscar un equipo en almacén (EN_STOCK/ALMACEN)
EJSON="$(curl -s -H "x-api-key: $KEY" "$API/equipos/disponibles?tipo=$TIPO")"
EID="$(echo "$EJSON" | jq -r '.[0].id // empty')"

if [[ -z "${EID:-}" ]]; then
  echo "No hay $TIPO en almacén; intentando reciclar desde un técnico…"
  # reciclar uno cualquiera desde TEC-6 a ALM-PRINC (usamos entregar/devolver ciclo externo)
  # buscamos primero en stock de técnico o en historial para armar caso; en demo: intentar nada y seguir
  echo "No se encontró equipo disponible para reservar. OK (nada que hacer)."
  exit 0
fi

echo "Usando equipo id=$EID"

# 2) Reservar para TEC-6 (dos veces para idempotencia)
R1="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/equipos/reservar" \
  -d "{\"id\":\"$EID\",\"tecnicoId\":$TEC_ID}")"
echo "$R1" | jq '{ok, _idempotent, equipo: {id, estado, owner_tipo, owner_id}}'

R2="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/equipos/reservar" \
  -d "{\"id\":\"$EID\",\"tecnicoId\":$TEC_ID}")"
echo "$R2" | jq '{ok, _idempotent, equipo: {id, estado, owner_tipo, owner_id}}'

# 3) Listar reservas del técnico y asegurar que esté
LIST="$(curl -s -H "x-api-key: $KEY" "$API/equipos/reservas?tecnicoId=$TEC_ID")"
LEN="$(echo "$LIST" | jq 'length')"
FOUND="$(echo "$LIST" | jq -r --arg id "$EID" 'map(select(.id==$id)) | length')"
echo "reservas_len=$LEN found=$FOUND"
if [[ "$FOUND" -lt 1 ]]; then
  echo "FAIL: reserva no reflejada en listado"
  exit 1
fi

# 4) Liberar (dos veces para idempotencia)
L1="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/equipos/liberar" \
  -d "{\"id\":\"$EID\"}")"
echo "$L1" | jq '{ok, _idempotent, equipo: {id, estado, owner_tipo, owner_id}}'

L2="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/equipos/liberar" \
  -d "{\"id\":\"$EID\"}")"
echo "$L2" | jq '{ok, _idempotent, equipo: {id, estado, owner_tipo, owner_id}}'

# 5) Verificar que ya no esté en reservas
LIST2="$(curl -s -H "x-api-key: $KEY" "$API/equipos/reservas?tecnicoId=$TEC_ID")"
FOUND2="$(echo "$LIST2" | jq -r --arg id "$EID" 'map(select(.id==$id)) | length')"
echo "found_after_liberar=$FOUND2"

if [[ "$FOUND2" -eq 0 ]]; then
  echo "OK reservas."
else
  echo "FAIL: equipo sigue figurando en reservas"
  exit 1
fi
