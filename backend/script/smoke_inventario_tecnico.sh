#!/usr/bin/env bash
set -euo pipefail
API="${API:-http://localhost:3000/v1}"
KEY="${KEY:-superdev}"
TEC="${1:-6}"

echo "== Inventario por técnico (TEC-${TEC}) =="
curl -sS -H "x-api-key: ${KEY}" "${API}/inventario/tecnicos/${TEC}/stock" | jq .
echo
echo "== Vista stock_almacen (referencia) =="
docker compose exec -T db psql -U ispuser -d ispdb -c \
  "SELECT * FROM public.stock_almacen ORDER BY almacen_codigo, material_id;"
