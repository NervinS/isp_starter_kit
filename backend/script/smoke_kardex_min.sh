#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:3000}"
API="${API_BASE%/}/v1"
API_KEY="${KEY:-superdev}"

CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-1}"
CURL_MAX_TIME="${CURL_MAX_TIME:-2}"

echo "=== 🧪 Smoke Kardex (mínimo) ==="

# Readiness /health (sin /v1)
echo "⏳ Esperando API en ${API_BASE}…"
ready="false"
for i in {1..60}; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" "${API_BASE%/}/health" || true)"
  if [[ "$code" == "200" ]]; then ready="true"; break; fi
  sleep 1
done
[[ "$ready" == "true" ]] || { echo "❌ API no respondió /health"; exit 1; }

# Consulta simple de kardex (últimos 50)
resp="$(curl -sS -w '\n%{http_code}' --connect-timeout "${CURL_CONNECT_TIMEOUT}" --max-time "${CURL_MAX_TIME}" -H "x-api-key: ${API_KEY}" "${API}/inventario/kardex")"
code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
echo "→ GET /inventario/kardex => HTTP ${code}"
echo "$body" | jq '.[0:3]' || true

[[ "$code" =~ ^2[0-9][0-9]$ ]] || { echo "❌ kardex HTTP $code"; exit 1; }

echo "✅ Smoke Kardex OK"
