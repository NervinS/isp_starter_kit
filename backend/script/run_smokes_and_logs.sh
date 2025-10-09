#!/usr/bin/env bash
set -Eeuo pipefail

export KEY="${KEY:-superdev}"
export API_BASE="${API_BASE:-http://localhost:3000}"

timestamp="$(date +%Y%m%d-%H%M%S)"

# API logs solo de esta corrida
docker compose logs -f api > "api_tail.${timestamp}.log" &
API_LOG_PID=$!

# Ejecuta smokes
./script/smoke_inventory.sh       2>&1 | tee "smoke_inventory.${timestamp}.log"
./script/smoke_inventario_traslado.sh 2>&1 | tee "smoke_inventario_traslado.${timestamp}.log"

# Detener follow
kill "${API_LOG_PID}" || true

echo "→ Logs guardados:"
echo "   - api_tail.${timestamp}.log"
echo "   - smoke_inventory.${timestamp}.log"
echo "   - smoke_inventario_traslado.${timestamp}.log"
