#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://127.0.0.1:3000}/v1"
API_KEY="${KEY:-superdev}"

echo "=== 🧪 Smoke Kardex (mínimo) ==="

# Sanity de salud
for i in {1..60}; do
  if curl -sf -H "x-api-key: ${API_KEY}" "${API}/health" >/dev/null; then break; fi
  sleep 1
done

# Consulta simple de kardex (últimos 50)
RESP=$(curl -sS -w '\n%{http_code}' -H "x-api-key: ${API_KEY}" "${API}/inventario/kardex")
CODE="${RESP##*$'\n'}"; BODY="${RESP%$'\n'*}"
echo "→ GET /inventario/kardex => HTTP ${CODE}"
echo "$BODY" | jq '.[0:3]' || true   # muestra primeras 3 filas

[[ "$CODE" =~ ^2[0-9][0-9]$ ]] || { echo "❌ kardex HTTP $CODE"; exit 1; }

echo "✅ Smoke Kardex OK"
