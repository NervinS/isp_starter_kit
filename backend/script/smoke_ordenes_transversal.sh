#!/usr/bin/env bash
# script/smoke_ordenes_transversal.sh
set -euo pipefail

echo "=== 🧪 Smoke Órdenes – contrato transversal ==="
API="${API:-http://localhost:3000/v1}"

PSQL="docker compose exec -T db psql -U ispuser -d ispdb -At -X -q"

pick_orden_codigo() {
  # Preferimos INS reciente; si no hay, cualquiera
  local code
  code="$($PSQL -c "SELECT codigo FROM public.ordenes WHERE tipo='INS' ORDER BY created_at DESC LIMIT 1;")" || true
  if [[ -z "${code// }" ]]; then
    code="$($PSQL -c "SELECT codigo FROM public.ordenes ORDER BY created_at DESC LIMIT 1;")" || true
  fi
  echo "$code"
}

ORD="$(pick_orden_codigo)"
if [[ -z "${ORD// }" ]]; then
  echo "✗ No hay órdenes en la base (nada que probar)."
  exit 1
fi

echo "→ GET /ordenes/${ORD}"
set +e
resp="$(curl -sS -w '\n%{http_code}' "${API}/ordenes/${ORD}")"
code=$?
set -e
if [[ $code -ne 0 ]]; then
  echo "✗ curl error (exit=$code)"
  exit $code
fi

status="${resp##*$'\n'}"
body="${resp%$'\n'$status}"

if [[ "$status" != 2* ]]; then
  echo "$body"
  echo "✗ HTTP $status"
  exit 22
fi

echo "✅ smoke_ordenes_transversal OK"
