#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"

echo "== equipos/historial por SN y MAC =="

# Tomamos uno de los equipos existentes para probar (primero buscamos por tipo ONU y luego usamos su SN/MAC)
eid="$(curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=ONU" | jq -r '.[0].id // empty')"

if [[ -z "${eid:-}" ]]; then
  # Si no hay en almacén, busca cualquiera (ONU o REPETIDOR) en la tabla (estado actual) — solo para obtener SN/MAC
  # Nota: endpoint interno de stock por técnico/almacén ya lo tienes; aquí hacemos una consulta directa a /docs-json para no
  # depender de SQL. Preferimos reutilizar disponibles de REPETIDOR si hay.
  eid="$(curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=REPETIDOR" | jq -r '.[0].id // empty')"
fi

if [[ -z "${eid:-}" ]]; then
  echo "No fue posible encontrar un equipo disponible de forma simple; prueba manual:"
  echo "  curl -s -H 'x-api-key: $KEY' \"$API/v1/equipos/disponibles?tipo=ONU|REPETIDOR\" | jq ."
  exit 0
fi

# Con el id, recuperamos su SN/MAC actual (usamos /v1/equipos/disponibles?tipo=... de nuevo para obtener los campos)
# Buscamos en ambos listados por si el id está en REPETIDOR o ONU
row="$( (curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=ONU"; \
         curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=REPETIDOR") \
        | jq -c ".[] | select(.id==\"$eid\")" | head -n1)"

sn="$(echo "$row" | jq -r '.sn')"
mac="$(echo "$row" | jq -r '.mac')"

echo "-- por SN = $sn"
curl -s -H "x-api-key: $KEY" "$API/v1/equipos/historial?sn=$sn" | jq '{equipo, historial_len: (.historial|length)}'

echo "-- por MAC = $mac"
curl -s -H "x-api-key: $KEY" "$API/v1/equipos/historial?mac=$mac" | jq '{equipo, historial_len: (.historial|length)}'

echo "OK historial."
