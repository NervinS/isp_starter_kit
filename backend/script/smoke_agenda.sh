#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://localhost:3000}"
JQ="${JQ_BIN:-jq}"

say() { echo -e "\n▶ $*"; }

# 1) Crear venta
say "Crear venta"
CREA=$(curl -s -X POST "$API/v1/ventas" -H 'content-type: application/json' \
  -d '{"cliente_nombre":"Ana","cliente_apellido":"Pérez","documento":"CC123","plan":"FTTH 100M","total":30.00}')
VTA=$(echo "$CREA" | $JQ -r '.codigo')
test "$VTA" != "null"

# 2) Evidencia mínima (firma)
say "Subir evidencia (firma)"
curl -s -X POST "$API/v1/ventas/$VTA/evidencias" -H 'content-type: application/json' \
  -d '{"firma_key":"evidencias/ventas/CC123/firma.png"}' >/dev/null

# 3) Pagar (idempotente)
say "Pagar venta (idempotente)"
KEY="pay-$(date +%s%3N)"
curl -s -X POST "$API/v1/ventas/$VTA/pagar" -H "Idempotency-Key: $KEY" | $JQ -e '.venta.codigo=="'"$VTA"'"' >/dev/null
curl -s -X POST "$API/v1/ventas/$VTA/pagar" -H "Idempotency-Key: $KEY" | $JQ -e '._idempotent==true' >/dev/null

# 4) Asegurar INS (si estaba anulada, recrea)
say "Asegurar INS"
ASEG=$(curl -s -X POST "$API/v1/ventas/$VTA/asegurar-ins")
ORD=$(echo "$ASEG" | $JQ -r '.codigo // .orden.codigo // empty')
if [ -z "${ORD:-}" ] || [ "$ORD" = "null" ]; then
  # tomar del detalle
  DET=$(curl -s "$API/v1/ventas/$VTA")
  ORD=$(echo "$DET" | $JQ -r '.orden.codigo')
fi
test -n "$ORD"

# 5) Asignar
say "Asignar $ORD"
curl -s -X POST "$API/v1/agenda/ordenes/$ORD/asignar" -H 'content-type: application/json' \
  -d '{"fecha":"2025-10-10","turno":"AM"}' | $JQ -e '.estado=="agendada"' >/dev/null

# 6) Reagendar (motivo opcional, validable)
say "Reagendar $ORD"
curl -s -X POST "$API/v1/agenda/ordenes/$ORD/reagendar" -H 'content-type: application/json' \
  -d '{"fecha":"2025-10-11","turno":"PM","motivo":"Solicitud del cliente"}' | $JQ -e '.estado=="agendada"' >/dev/null

# 7) Cancelar (idempotente)
say "Cancelar $ORD"
curl -s -X POST "$API/v1/agenda/ordenes/$ORD/cancelar" -H 'content-type: application/json' \
  -d '{"motivo":"Cliente no disponible"}' | $JQ -e '.estado=="cancelada"' >/dev/null
curl -s -X POST "$API/v1/agenda/ordenes/$ORD/cancelar" -H 'content-type: application/json' \
  -d '{"motivo":"Cliente no disponible"}' | $JQ -e '.estado=="cancelada"' >/dev/null

# 8) Catálogo de motivos de anulación
say "Obtener catálogo motivos de anulación"
CAT=$(curl -s "$API/v1/catalogos/motivos-anulacion")
MID=$(echo "$CAT" | $JQ -r '.items[] | select(.nombre=="No hay cobertura final") | .id' | head -n1)
test -n "$MID"

# 9) Anular con motivoId (si ya está anulada, debe persistir/retornar el mismo motivo)
say "Anular $ORD con motivoId=$MID"
ANU1=$(curl -s -X POST "$API/v1/agenda/ordenes/$ORD/anular" -H 'content-type: application/json' \
  -d '{"motivoId":"'"$MID"'"}')
echo "$ANU1" | $JQ -e '.estado=="anulada"' >/dev/null
echo "$ANU1" | $JQ -e '.motivoAnulacionId=='"$MID"'' >/dev/null

say "Idempotencia anulación $ORD"
ANU2=$(curl -s -X POST "$API/v1/agenda/ordenes/$ORD/anular" -H 'content-type: application/json' \
  -d '{"motivoId":"'"$MID"'"}')
echo "$ANU2" | $JQ -e '.estado=="anulada"' >/dev/null
echo "$ANU2" | $JQ -e '.motivoAnulacionId=='"$MID"'' >/dev/null

say "✔ Smoke agenda OK (venta=$VTA, orden=$ORD)"
