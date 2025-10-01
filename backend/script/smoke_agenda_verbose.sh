#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://localhost:3000}"
echo "SMOKE AGENDA (VERBOSO)  API=${API}"

say() { printf "\n────────────────────────────────────────────────────────\n▶ %s\n" "$*"; }

# req METHOD URL [DATA_JSON or "" ] [HEADER or ""]
req() {
  local m="$1"; shift
  local u="$1"; shift
  local data="${1:-}"; shift || true
  local header="${1:-}"; shift || true

  echo "→ ${m} ${u}"
  [[ -n "$data" ]] && { echo "   (payload abajo si aplica)"; echo "   ${data}"; }

  local curl_args=(-sS -w $'\n%{http_code}' -X "$m" "$u")
  [[ -n "$header" ]] && curl_args+=(-H "$header")
  if [[ -n "$data" ]]; then
    curl_args+=(-H 'content-type: application/json' -d "$data")
  fi

  R=$(curl "${curl_args[@]}")
  HTTP="${R##*$'\n'}"
  BODY="${R%$'\n'*}"
  echo "  HTTP ${HTTP}"
  echo "${BODY}" | jq . || true
  [[ "${HTTP}" =~ ^2[0-9][0-9]$ ]]
}

# 1) Crear venta
say "Crear venta"
CREA_BODY='{"cliente_nombre":"Ana","cliente_apellido":"Pérez","documento":"CC123","plan":"FTTH 100M","total":30.00}'
req POST "${API}/v1/ventas" "${CREA_BODY}"
VTA=$(echo "$BODY" | jq -r '.codigo')
echo "   venta: ${VTA}"

# 2) Subir evidencia mínima
say "Subir evidencia (firma)"
EVD_BODY='{"firma_key":"evidencias/ventas/CC123/firma.png","cedula_key":"evidencias/ventas/CC123/cedula.png","recibo_key":"evidencias/ventas/CC123/recibo.png"}'
req POST "${API}/v1/ventas/${VTA}/evidencias" "${EVD_BODY}"

# 3) Pagar idempotente (con Idempotency-Key)
say "Pagar (idempotente)"
KEY="pay-$(date +%s%3N)"
req POST "${API}/v1/ventas/${VTA}/pagar" "" "Idempotency-Key: ${KEY}"
# replay con la MISMA llave
req POST "${API}/v1/ventas/${VTA}/pagar" "" "Idempotency-Key: ${KEY}"
echo "   Idempotency-Key usada: ${KEY}"

# 4) Asegurar INS y consultar la orden
say "Asegurar INS"
req POST "${API}/v1/ventas/${VTA}/asegurar-ins" ""
req GET  "${API}/v1/ventas/${VTA}" ""
ORD=$(echo "$BODY" | jq -r '.orden.codigo')
echo "   orden: ${ORD}"

# 5) Asignar
say "Asignar ${ORD}"
ASIG_BODY='{"fecha":"2025-10-10","turno":"AM"}'
req POST "${API}/v1/agenda/ordenes/${ORD}/asignar" "${ASIG_BODY}"

# 6) Reagendar con motivo desde catálogo (por NOMBRE)
say "Reagendar ${ORD} (motivo desde catálogo)"
req GET "${API}/v1/catalogos/motivos-reagenda" ""
PREFER="Solicitud del cliente"
HAS_PREF=$(echo "$BODY" | jq -r --arg n "$PREFER" '.items[]? | select(.nombre==$n) | .nombre' || true)
if [[ -n "${HAS_PREF:-}" ]]; then
  MOTIVO_REAG="${HAS_PREF}"
else
  MOTIVO_REAG=$(echo "$BODY" | jq -r '.items[0].nombre')
fi
if [[ -z "${MOTIVO_REAG}" || "${MOTIVO_REAG}" == "null" ]]; then
  echo "❌ No hay motivos activos en catálogo de reagenda. Aborto." >&2
  exit 1
fi
echo "   motivo elegido: ${MOTIVO_REAG}"
REAG_BODY=$(jq -nc --arg f "2025-10-11" --arg t "PM" --arg m "$MOTIVO_REAG" '{fecha:$f, turno:$t, motivo:$m}')
req POST "${API}/v1/agenda/ordenes/${ORD}/reagendar" "${REAG_BODY}"

# 7) Cancelar (texto libre)
say "Cancelar ${ORD} (texto libre)"
CANC_BODY='{"motivo":"Cliente no disponible"}'
req POST "${API}/v1/agenda/ordenes/${ORD}/cancelar" "${CANC_BODY}"

# 8) Anular con motivoId desde catálogo real
say "Anular ${ORD} (motivoId desde catálogo)"
req GET "${API}/v1/catalogos/motivos-anulacion" ""
PREFER_ANU="No hay cobertura final"
HAS_PREF_ANU=$(echo "$BODY" | jq -r --arg n "$PREFER_ANU" '.items[]? | select(.nombre==$n) | .id' || true)
if [[ -n "${HAS_PREF_ANU:-}" ]]; then
  MOTIVO_ANU_ID="${HAS_PREF_ANU}"
else
  MOTIVO_ANU_ID=$(echo "$BODY" | jq -r '.items[0].id')
fi
if [[ -z "${MOTIVO_ANU_ID}" || "${MOTIVO_ANU_ID}" == "null" ]]; then
  echo "❌ No hay motivos activos en catálogo de anulación. Aborto." >&2
  exit 1
fi
echo "   motivoId elegido: ${MOTIVO_ANU_ID}"
ANU_BODY=$(jq -nc --arg id "$MOTIVO_ANU_ID" '{motivoId:$id}')
req POST "${API}/v1/agenda/ordenes/${ORD}/anular" "${ANU_BODY}"
# idempotente
req POST "${API}/v1/agenda/ordenes/${ORD}/anular" "${ANU_BODY}"

echo -e "\n✅ SMOKE OK"
