#!/usr/bin/env bash
# script/smoke_metrics.sh
# Acepta Prometheus text/plain o JSON; solo exige HTTP 200 y contenido no vacío.
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"

say(){ echo -e "$@"; }

say "=== 🧪 smoke_metrics ==="
say "API=${API}"

# Trae cuerpo + código sin fallar en no-200
out_and_code="$(curl -sS -w '\n%{http_code}' -H "x-api-key: ${KEY}" "${API}/metrics")" || true
code="$(tail -n1 <<< "${out_and_code}")"
body="$(sed '$d' <<< "${out_and_code}")"

if [[ "${code}" != "200" ]]; then
  echo "❌ /metrics -> HTTP ${code}"
  echo "${body}"
  exit 1
fi

# Contenido no vacío
if [[ -z "${body//[[:space:]]/}" ]]; then
  echo "❌ /metrics vacío"
  exit 1
fi

# Si parece JSON, valida; si no, valida formato Prometheus básico
if [[ "${body}" =~ ^[[:space:]]*\\{ ]]; then
  echo "${body}" | jq -e 'type=="object"' >/dev/null
else
  # Prometheus: al menos una línea de métrica (no comentarios) con "name value"
  # Ignora líneas que empiezan con '#'
  metric_line="$(grep -v '^[[:space:]]*#' <<< "${body}" | grep -E '^[a-zA-Z_:][a-zA-Z0-9_:]*[[:space:]][0-9eE+.-]')"
  if [[ -z "${metric_line}" ]]; then
    echo "❌ /metrics no parece Prometheus ni JSON"
    exit 1
  fi
fi

say "✅ smoke_metrics OK"
