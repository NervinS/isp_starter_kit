#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://127.0.0.1:3000}"
TEC_ID="${TEC_ID:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"

echo "Esperando health 200 en $API/v1/health ..."
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/v1/health")" = "200" ]; do sleep 1; done
echo "OK health"

OID="MAN-TEST-$(date +%Y%m%d%H%M%S)"
echo "Creando agenda (no garantiza existencia de la orden física, solo agenda)..."
curl -s -X POST "$API/v1/agenda/ordenes/$OID/asignar" \
  -H "Authorization: Bearer dummy" -H "Content-Type: application/json" \
  -d "{\"tecnicoId\":\"$TEC_ID\",\"fecha\":\"$(date -I)\",\"turno\":\"am\"}" >/dev/null || true

echo
echo "=== BYPASS ON (esperado 404 si la orden REAL no existe) ==="
docker compose stop api >/dev/null
docker compose run --rm -e SMOKE_BYPASS_TECH_GUARD=1 api true >/dev/null
docker compose up -d api >/dev/null
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/v1/health")" = "200" ]; do sleep 1; done

code_on=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$OID/iniciar" -H "Authorization: Bearer dummy")
echo "Resultado iniciar con BYPASS=1 -> HTTP $code_on"

echo
echo "=== BYPASS OFF (esperado 403 por guard de JWT) ==="
docker compose stop api >/dev/null
docker compose run --rm -e SMOKE_BYPASS_TECH_GUARD=0 api true >/dev/null
docker compose up -d api >/dev/null
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/v1/health")" = "200" ]; do sleep 1; done

code_off=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$OID/iniciar" -H "Authorization: Bearer dummy")
echo "Resultado iniciar con BYPASS=0 -> HTTP $code_off"

echo
if [[ "$code_on" == "404" && "$code_off" == "403" ]]; then
  echo "✅ Circulo cerrado: el bypass de JWT funciona (403→404). Para 200, hay que generar la orden real en la DB/flujo."
  exit 0
else
  echo "❌ Algo no cuadra. Revisa logs de 'api' y que el hotfix se aplicó al arranque."
  exit 1
fi
