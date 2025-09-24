#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"

echo "▶ Esperando /v1/health en $API_BASE… (máx 120s)"
for i in {1..120}; do
  if curl -fsS "$API_BASE/v1/health" >/dev/null; then echo "✓ API OK"; break; fi
  sleep 1
done

echo
echo "▶ Payload de salud:"
curl -fsS "$API_BASE/v1/health"

echo
echo "▶ GET público (kebab): /v1/catalogos/motivos-reagenda"
curl -fsS "$API_BASE/v1/catalogos/motivos-reagenda" >/dev/null && echo "✓ kebab OK"

echo
echo "▶ GET público (underscore): /v1/catalogos/motivos_reagenda/items?soloActivos=true"
curl -fsS "$API_BASE/v1/catalogos/motivos_reagenda/items?soloActivos=true" >/dev/null && echo "✓ underscore OK"

echo
echo "▶ Obteniendo JWT_SECRET desde el contenedor 'api'"
JWT_SECRET="$(docker compose exec -T api sh -lc 'echo -n $JWT_SECRET')"
[[ -n "$JWT_SECRET" ]] && echo "✓ JWT_SECRET obtenido" || { echo "✗ No se pudo leer JWT_SECRET"; exit 1; }

echo
echo "▶ Generando token ADMIN dentro del contenedor (role=admin + roles[admin])"
docker compose exec -T api node -e \
"const jwt=require('jsonwebtoken');console.log(
  jwt.sign({sub:'ADMIN-USER',role:'admin',roles:['admin'],scopes:['catalogos:write']},
  process.env.JWT_SECRET,{expiresIn:'2h'}))" > /tmp/jwt_admin.txt
AUTH_ADMIN="Authorization: Bearer $(cat /tmp/jwt_admin.txt)"
echo "✓ Token admin listo"

echo
echo "▶ GET admin lista"
curl -fsS -H "$AUTH_ADMIN" "$API_BASE/v1/admin/catalogos/motivos_reagenda/items" >/dev/null || true

echo
NAME="SMOKE_$(date +%s)"
echo "▶ POST admin crear '$NAME'"
CREATE_JSON="$(curl -fsS -H "$AUTH_ADMIN" -H 'Content-Type: application/json' \
  -d "{\"nombre\":\"$NAME\",\"activo\":true,\"orden\":95}" \
  "$API_BASE/v1/admin/catalogos/motivos_reagenda/items")"
echo "$CREATE_JSON" | jq -C . || echo "$CREATE_JSON"
echo "✓ smoke_catalogos.sh OK"
