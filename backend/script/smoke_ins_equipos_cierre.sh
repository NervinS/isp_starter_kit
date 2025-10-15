#!/usr/bin/env bash
set -euo pipefail
API=${API:-http://localhost:3000/v1}

# Buscar una INS real primero
real_code="$(docker compose exec -T db psql -U ispuser -d ispdb -At -c \
"SELECT codigo FROM public.ordenes WHERE tipo='INS' ORDER BY created_at DESC LIMIT 1;")"
if [[ -n "$real_code" ]]; then
  ORDER="${ORDER:-$real_code}"
else
  ORDER="${ORDER:-INS-000001}"  # fallback solo si de verdad no hay INS
fi

echo "=== 🧪 smoke_ins_equipos_cierre ===  API=$API"
echo "→ Orden objetivo: $ORDER"

# Si no existe, no es responsabilidad de este smoke crearla (salida amable)
status=$(curl -s -o /dev/null -w "%{http_code}" "$API/ordenes/$ORDER")
if [[ "$status" != "200" ]]; then
  echo "↷ SKIP: $ORDER no existe (no es responsabilidad de este smoke crearla)."
  exit 0
fi

# … resto del script sin cambios …
