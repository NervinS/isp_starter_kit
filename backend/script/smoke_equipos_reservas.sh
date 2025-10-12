#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
TIPO="${TIPO:-ONU}"
TEC="${TEC:-6}"

wait_api() {
  local url="${API%/}/../health"
  # normaliza .../v1 -> .../health
  url="$(python3 - <<'PY'
import os,sys,urllib.parse
api=os.environ.get("API","http://localhost:3000/v1")
root=api.rsplit("/v",1)[0]
print(root+"/health")
PY
)"
  for s in 1 1 2 3 5 8 13; do
    if curl -fsS "$url" >/dev/null; then return 0; fi
    sleep "$s"
  done
  # último intento “fuerte” para devolver error útil
  curl -fsS "$url" || exit 1
}

echo "== equipos: reservas (tipo=${TIPO}) =="
wait_api

R="$(curl -fsS "$API/equipos/reservas?tipo=${TIPO}")"
TOTAL="$(jq -r '.total // 0' <<<"$R" 2>/dev/null || echo 0)"

if [[ "$TOTAL" -lt 1 ]]; then
  curl -fsS -X POST "$API/equipos/reservar-auto" \
    -H 'Content-Type: application/json' \
    -d "{\"tipo\":\"${TIPO}\",\"tecnicoId\":${TEC}}" >/dev/null
  R="$(curl -fsS "$API/equipos/reservas?tipo=${TIPO}")"
  TOTAL="$(jq -r '.total // 0' <<<"$R" 2>/dev/null || echo 0)"
fi

echo "ok=true, total=${TOTAL}"
jq -c '.items' <<<"$R" 2>/dev/null || echo "[]"
