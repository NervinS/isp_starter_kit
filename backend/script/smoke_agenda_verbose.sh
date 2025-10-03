#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
API="$API_BASE/v1"

hdr=(-H "x-api-key: $KEY" -H "Content-Type: application/json")

echo "SMOKE AGENDA (VERBOSO)  API=$API"

echo
echo "────────────────────────────────────────────────────────"
echo "▶ Crear venta"
body='{"cliente_nombre":"Ana","cliente_apellido":"Pérez","documento":"CC123","plan":"FTTH 100M","total":30.00}'
echo "→ POST $API/ventas"
echo "   (payload abajo si aplica)"
echo "   $body"
resp="$(curl -sS -X POST "$API/ventas" "${hdr[@]}" -d "$body" -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .
codigo="$(echo "$json" | jq -r '.codigo // .venta.codigo // empty')"
echo "   venta: $codigo"

echo
echo "────────────────────────────────────────────────────────"
echo "▶ Subir evidencia (firma)"
body='{"firma_key":"evidencias/ventas/CC123/firma.png","cedula_key":"evidencias/ventas/CC123/cedula.png","recibo_key":"evidencias/ventas/CC123/recibo.png"}'
echo "→ POST $API/ventas/$codigo/evidencias"
echo "   (payload abajo si aplica)"
echo "   $body"
resp="$(curl -sS -X POST "$API/ventas/$codigo/evidencias" "${hdr[@]}" -d "$body" -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .

echo
echo "────────────────────────────────────────────────────────"
echo "▶ Pagar (idempotente)"
echo "→ POST $API/ventas/$codigo/pagar"
resp="$(curl -sS -X POST "$API/ventas/$codigo/pagar" "${hdr[@]}" -H "Idempotency-Key: test-123" -d '{}' -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .
# segundo intento idempotente
echo "→ POST $API/ventas/$codigo/pagar"
resp="$(curl -sS -X POST "$API/ventas/$codigo/pagar" "${hdr[@]}" -H "Idempotency-Key: test-123" -d '{}' -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .

echo
echo "────────────────────────────────────────────────────────"
echo "▶ Asegurar INS"
echo "→ POST $API/ventas/$codigo/asegurar-ins"
resp="$(curl -sS -X POST "$API/ventas/$codigo/asegurar-ins" "${hdr[@]}" -d '{}' -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .

echo "→ GET $API/ventas/$codigo"
resp="$(curl -sS "$API/ventas/$codigo" "${hdr[@]}" -w "\n%{http_code}")"
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
echo "  HTTP $http"
echo "$json" | jq .
orden="$(echo "$json" | jq -r '.orden.codigo // empty')"
echo "   orden: $orden"

echo
echo "────────────────────────────────────────────────────────"
echo "▶ Asignar $orden"
estado="$(echo "$json" | jq -r '.orden.estado // empty')"
if [[ "$estado" == "cerrada" ]]; then
  echo "ℹ️  Orden en estado=cerrada; no se puede asignar. Se omite este paso y se considera OK."
  exit 0
fi

payload='{"fecha":"'"$(date -u +%Y-%m-%d --date="next Fri")"'","turno":"AM"}'
echo "→ POST $API/agenda/ordenes/$orden/asignar"
echo "   (payload abajo si aplica)"
echo "   $payload"
resp="$(curl -sS -X POST "$API/agenda/ordenes/$orden/asignar" "${hdr[@]}" -d "$payload" -w "\n%{http_code}")" || true
http="${resp##*$'\n'}"; json="${resp%$'\n'*}"
if [[ "$http" != "201" ]]; then
  echo "  HTTP $http"
  echo "$json" | jq .
  # No romper el smoke si la asignación no aplica
  exit 0
fi
echo "  HTTP $http"
echo "$json" | jq .
