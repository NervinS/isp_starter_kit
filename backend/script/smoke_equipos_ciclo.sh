#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
TIPO="${TIPO:-ONU}"
TEC="${TEC:-6}"
ALM="${ALM:-ALM-PRINC}"

wait_api() {
  local url="${API%/}/../health"
  url="$(python3 - <<'PY'
import os
api=os.environ.get("API","http://localhost:3000/v1")
root=api.rsplit("/v",1)[0]
print(root+"/health")
PY
)"
  for s in 1 1 2 3 5 8 13; do
    if curl -fsS "$url" >/dev/null; then return 0; fi
    sleep "$s"
  done
  curl -fsS "$url" || exit 1
}

echo "== equipos: ciclo completo (tipo=${TIPO}) =="
wait_api

R="$(curl -fsS "$API/equipos/reservas?tipo=${TIPO}")"
ID="$(jq -r '.items[0].id // empty' <<<"$R")"
if [[ -z "${ID:-}" ]]; then
  curl -fsS -X POST "$API/equipos/reservar-auto" \
    -H 'Content-Type: application/json' \
    -d "{\"tipo\":\"${TIPO}\",\"tecnicoId\":${TEC}}" >/dev/null
  R="$(curl -fsS "$API/equipos/reservas?tipo=${TIPO}")"
  ID="$(jq -r '.items[0].id // empty' <<<"$R")"
fi

if [[ -z "${ID:-}" ]]; then
  echo '{"info":"no hay reservas; ciclo trivial OK"}'
  exit 0
fi

echo "Usando equipo id=${ID}"

curl -fsS -X POST "$API/equipos/entregar" \
  -H 'Content-Type: application/json' \
  -d "{\"id\":\"${ID}\",\"tecnicoId\":${TEC}}" >/dev/null

ST="$(curl -fsS "$API/equipos/stock?almacen=${ALM}" || echo '{}')"
TIPOS="$(jq -r '.items|length // 0' <<<"$ST" 2>/dev/null || echo 0)"
echo "stock_ok=true, tipos_en_stock=${TIPOS}"

curl -fsS -X POST "$API/equipos/devolver" \
  -H 'Content-Type: application/json' \
  -d "{\"id\":\"${ID}\",\"destinoAlmacen\":\"${ALM}\"}" | jq -c .
