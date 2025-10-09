#!/usr/bin/env bash
set -euo pipefail
API=${API:-http://localhost:3000}

curl -sSf "$API/health" >/dev/null

CODIGO=$(curl -sS "$API/v1/ventas" \
  | jq -r '[.[] | select(.estado=="pagada")][-1].codigo // (.[-1].codigo // empty)')
test -n "$CODIGO"

R1=$(curl -sS -X POST "$API/v1/ventas/$CODIGO/asegurar-ins")
INS1=$(echo "$R1" | jq -r '.codigo // .orden.codigo // empty')
test -n "$INS1"

R2=$(curl -sS -X POST "$API/v1/ventas/$CODIGO/asegurar-ins")
INS2=$(echo "$R2" | jq -r '.codigo // .orden.codigo // empty')
if [[ "$INS1" != "$INS2" ]]; then
  echo "Fallo: no es idempotente ($INS1 vs $INS2)"
  exit 1
fi

echo "OK: idempotente ($INS1)"
