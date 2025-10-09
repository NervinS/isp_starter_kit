#!/usr/bin/env bash
# script/smoke_jobs.sh
# Verifica /v1/jobs/simular-cortes y /v1/jobs/simular-reconexiones
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"

say(){ echo -e "$@"; }

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1-}"
  if [[ -n "${data}" ]]; then
    curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" -X "${method}" -d "${data}" "${url}"
  else
    curl -sfS -H "x-api-key: ${KEY}" -X "${method}" "${url}"
  fi
}

say "=== 🧪 smoke_jobs ==="
say "API=${API}"

# 1) simular-cortes
r1="$(curl_json POST "${API}/jobs/simular-cortes" '{}')"
echo "${r1}" | jq -e 'type=="object"' >/dev/null

# 2) simular-reconexiones
r2="$(curl_json POST "${API}/jobs/simular-reconexiones" '{}')"
echo "${r2}" | jq -e 'type=="object"' >/dev/null

say "✅ smoke_jobs OK"
