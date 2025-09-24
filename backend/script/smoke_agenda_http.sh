#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://127.0.0.1:3000}"
TEC_ID="${TECNICO_ID:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"

# Usamos token con sub (agenda no usa el guard de técnicos estricto)
SUB=$(./script/jwt_tecnico_variants.sh "$TEC_ID" | sed -n 's/^SUB=//p')
TOKEN="Bearer $SUB"
HDR_AUTH="Authorization: ${TOKEN}"
HDR_CT="Content-Type: application/json"

ORD="${ORDEN_CODIGO:-MAN-TEST-$(date +%Y%m%d%H%M%S)}"

# Crea orden si no existe
docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "
INSERT INTO ordenes (id, codigo, estado, creado_at, actualizado_at)
VALUES (gen_random_uuid(), '$ORD', 'creada', now(), now())
ON CONFLICT (codigo) DO NOTHING;" >/dev/null

echo "== Agenda HTTP (orden=$ORD) =="

echo "-- ASIGNAR --"
curl -sfS -X POST "$API/v1/agenda/ordenes/$ORD/asignar" \
  -H "$HDR_AUTH" -H "$HDR_CT" \
  -d "{\"tecnicoId\":\"$TEC_ID\",\"fecha\":\"$(date -I)\",\"turno\":\"am\"}"

echo "-- REAGENDAR --"
curl -sfS -X POST "$API/v1/agenda/ordenes/$ORD/reagendar" \
  -H "$HDR_AUTH" -H "$HDR_CT" \
  -d "{\"fecha\":\"$(date -I -d 'tomorrow')\",\"turno\":\"pm\"}"

echo "-- CANCELAR --"
curl -sfS -X POST "$API/v1/agenda/ordenes/$ORD/cancelar" -H "$HDR_AUTH"

echo "✓ smoke_agenda_http OK"
