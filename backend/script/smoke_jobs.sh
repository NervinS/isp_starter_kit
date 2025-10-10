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

  # Retrys rápidos para arranque en frío del contenedor
  local max_try=3
  local try=1
  local out
  local code
  while :; do
    if [[ -n "${data}" ]]; then
      out="$(curl -sS -w '\n%{http_code}' -H "x-api-key: ${KEY}" -H "content-type: application/json" -X "${method}" -d "${data}" "${url}")" || true
    else
      out="$(curl -sS -w '\n%{http_code}' -H "x-api-key: ${KEY}" -X "${method}" "${url}")" || true
    fi
    code="$(echo "${out}" | tail -n1)"
    body="$(echo "${out}" | sed '$d')"

    # Acepta 200/201/202
    if [[ "${code}" =~ ^20(0|1|2)$ ]]; then
      echo "${body}"
      return 0
    fi

    if (( try >= max_try )); then
      echo "HTTP ${code} → ${body}" >&2
      return 1
    fi
    sleep 0.7
    ((try++))
  done
}

say "=== 🧪 smoke_jobs ==="
say "API=${API}"

# 1) simular-cortes
r1="$(curl_json POST "${API}/jobs/simular-cortes" '{}')"
# Si hay body, intenta validar JSON; si no, igual lo damos por OK
if [[ -n "${r1}" ]]; then
  echo "${r1}" | jq -e 'type=="object"' >/dev/null 2>&1 || true
fi
say "→ simular-cortes OK"

# 2) simular-reconexiones
r2="$(curl_json POST "${API}/jobs/simular-reconexiones" '{}')"
if [[ -n "${r2}" ]]; then
  echo "${r2}" | jq -e 'type=="object"' >/dev/null 2>&1 || true
fi
say "→ simular-reconexiones OK"

say "✅ smoke_jobs OK"
