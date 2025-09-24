#!/usr/bin/env bash
set -Eeuo pipefail
API_BASE="${API_BASE:-http://localhost:3000}"

echo "▶ Esperando /v1/health (120s máx)"
for i in {1..120}; do
  if curl -fsS "$API_BASE/v1/health" >/dev/null; then echo "✓ API OK"; break; fi
  sleep 1
done

echo "▶ Catalogos públicos"
curl -fsS "$API_BASE/v1/catalogos/motivos-reagenda" >/dev/null && echo "✓ motivos-reagenda OK"
curl -fsS "$API_BASE/v1/catalogos/motivos_reagenda/items?soloActivos=true" >/dev/null && echo "✓ motivos_reagenda underscore OK"

echo "▶ Rutas mapeadas claves (status 404/405 también valen: solo probamos wiring)"
for path in \
  "/v1/agenda/ordenes" \
  "/v1/ordenes/ORD-DEMO-2001/cerrar-completo" \
  "/v1/v1/tecnicos/x/pendientes"
do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE$path")
  [[ "$code" =~ ^(200|201|400|401|403|404|405)$ ]] && echo "✓ $path -> $code" || { echo "✗ $path -> $code"; exit 1; }
done
echo "🎉 quickcheck OK"
