#!/usr/bin/env bash
# smoke_ins_equipos_cierre.sh — verifica idempotencia de cierre de INS
# Pasa en verde si:
#  - La orden no existe (skip controlado), o
#  - La orden existe y el endpoint /cerrar responde 2xx/409 de forma idempotente.

set -Eeuo pipefail

API="${API:-http://localhost:3000/v1}"
ORDER="${ORDER:-INS-000001}"

b()      { printf "\033[1m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }

echo "=== 🧪 smoke_ins_equipos_cierre ===  API=${API}"
echo "→ Orden objetivo: ${ORDER}"

# --- Helper curl que no aborta por HTTP!=2xx; devuelve status y body ---
curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"
  if [[ -n "$data" ]]; then
    curl -sS -X "$method" "$url" \
      -H 'Content-Type: application/json' \
      --data "$data" -w '\n%{http_code}'
  else
    curl -sS -X "$method" "$url" -w '\n%{http_code}'
  fi
}

# 1) Chequear existencia de la orden
resp="$(curl_json GET "${API}/ordenes/${ORDER}")"
body="${resp%$'\n'*}"
code="${resp##*$'\n'}"

if [[ "$code" == "404" ]]; then
  yellow "↷ SKIP: ${ORDER} no existe (no es responsabilidad de este smoke crearla)."
  exit 0
elif [[ "$code" != "200" ]]; then
  red "✗ GET /ordenes/${ORDER} -> HTTP ${code}"
  echo "$body"
  exit 1
fi

# 2) Probar cierre idempotente dos veces con la MISMA Idempotency-Key
key="smoke-ins-cierre-$(date +%s)"
post_cerrar() {
  curl -sS -X POST "${API}/ordenes/${ORDER}/cerrar" \
    -H 'Content-Type: application/json' \
    -H "Idempotency-Key: ${key}" \
    --data '{}' -w '\n%{http_code}'
}

resp1="$(post_cerrar)"
body1="${resp1%$'\n'*}"
code1="${resp1##*$'\n'}"

# Acepta 2xx y 409 como "OK"
case "$code1" in
  20*|201|202|204|409) ;;
  *)
    red "✗ 1er POST /ordenes/${ORDER}/cerrar -> HTTP ${code1}"
    echo "$body1"
    exit 1
    ;;
esac

resp2="$(post_cerrar)"
body2="${resp2%$'\n'*}"
code2="${resp2##*$'\n'}"

case "$code2" in
  20*|201|202|204|409) ;;
  *)
    red "✗ 2do POST /ordenes/${ORDER}/cerrar (retry misma clave) -> HTTP ${code2}"
    echo "$body2"
    exit 1
    ;;
esac

green "OK smoke_ins_equipos_cierre (idempotente y tolerante a estado)"
exit 0
