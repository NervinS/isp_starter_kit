#!/usr/bin/env bash
# script/smoke_jobs.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"
SINCE="${SINCE:-30s}"

say(){ echo -e "$@"; }

curl_json_status() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1-}"

  if [[ -n "${data}" ]]; then
    curl -sS -H "x-api-key: ${KEY}" -H "content-type: application/json" \
         -X "${method}" -d "${data}" "${url}" \
         -w "\n%{http_code}" || true
  else
    curl -sS -H "x-api-key: ${KEY}" \
         -X "${method}" "${url}" \
         -w "\n%{http_code}" || true
  fi
}

say "=== 🧪 smoke_jobs ==="
say "API=${API}"
echo

echo "-- POST /jobs/simular-cortes"
resp_and_code="$(curl_json_status POST "${API}/jobs/simular-cortes" '{}')"
http_body="$(sed '$d' <<<"${resp_and_code}")"
http_code="$(tail -n1 <<<"${resp_and_code}")"
echo "${http_body}"
echo "HTTP status: ${http_code}"
echo "== recent api logs (${SINCE}) =="
docker compose --env-file ./.env logs --since "${SINCE}" api || true
echo "== end logs ==\\n"
echo

echo "-- POST /jobs/simular-reconexiones"
resp_and_code="$(curl_json_status POST "${API}/jobs/simular-reconexiones" '{}')"
http_body="$(sed '$d' <<<"${resp_and_code}")"
http_code="$(tail -n1 <<<"${resp_and_code}")"
echo "${http_body}"
echo "HTTP status: ${http_code}"
echo "== recent api logs (${SINCE}) =="
docker compose --env-file ./.env logs --since "${SINCE}" api || true
echo "== end logs ==\\n"

echo "✅ smoke_jobs finalizado (si ves >=400 arriba, ya tienes el JSON de error y el tramo de logs)."
