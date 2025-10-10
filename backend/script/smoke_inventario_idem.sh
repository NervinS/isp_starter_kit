#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"

CENTRAL="74564bfe-a758-4057-9cbf-9ece34601702"
TEC6="62ebd37f-44c4-499d-b9ed-7bee75b09275"
ALMPRINC="11111111-1111-1111-1111-111111111111"
MAT=5 # DROP-FO

echo "== Smoke inventario idempotencia =="

echo "-- Ingreso CENTRAL (idempotente)"
IDK="SMK-ING-$(date +%s)"
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"ingreso\",\"materialId\":$MAT,\"cantidad\":10,\"toAlmacenId\":\"$CENTRAL\",\"nota\":\"smoke ingreso\"}" >/dev/null
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"ingreso\",\"materialId\":$MAT,\"cantidad\":10,\"toAlmacenId\":\"$CENTRAL\",\"nota\":\"smoke ingreso\"}" >/dev/null

echo "-- Traslado CENTRAL -> TEC-6 (idempotente)"
IDK="SMK-TRL-$(date +%s)"
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT,\"cantidad\":4,\"fromAlmacenId\":\"$CENTRAL\",\"toAlmacenId\":\"$TEC6\",\"tecnicoId\":6,\"nota\":\"smoke traslado\"}" >/dev/null
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT,\"cantidad\":4,\"fromAlmacenId\":\"$CENTRAL\",\"toAlmacenId\":\"$TEC6\",\"tecnicoId\":6,\"nota\":\"smoke traslado\"}" >/dev/null

echo "-- Devolución TEC-6 -> ALM-PRINC (idempotente)"
IDK="SMK-DEV-$(date +%s)"
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT,\"cantidad\":2,\"fromAlmacenId\":\"$TEC6\",\"toAlmacenId\":\"$ALMPRINC\",\"tecnicoId\":6,\"nota\":\"smoke devolucion\"}" >/dev/null
curl -s -X POST "$API/v1/inventario/movimientos" \
  -H "content-type: application/json" -H "x-api-key: $KEY" -H "Idempotency-Key: $IDK" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT,\"cantidad\":2,\"fromAlmacenId\":\"$TEC6\",\"toAlmacenId\":\"$ALMPRINC\",\"tecnicoId\":6,\"nota\":\"smoke devolucion\"}" >/dev/null

echo "-- Saldos"
curl -s "$API/v1/inventario/tecnicos/6/stock" -H "x-api-key: $KEY" | jq '.'
curl -s "$API/v1/inventario/stock/almacen/CENTRAL" -H "x-api-key: $KEY" | jq '.'
curl -s "$API/v1/inventario/stock/almacen/ALM-PRINC" -H "x-api-key: $KEY" | jq '.'

echo "OK"
