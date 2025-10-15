#!/usr/bin/env bash
# script/smoke_tecnico_orden_detalle.sh
set -euo pipefail

echo "=== 🧪 Smoke Detalle Técnico de Orden ==="

API="${API:-http://localhost:3000/v1}"
echo "API=${API}"

PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q -At"

# curl helper que falla en 4xx/5xx y muestra info útil
try_code() {
  local code="$1"
  local url="${API}/tecnico/ordenes/${code}"
  echo "-- probando código: ${code}"

  set +e
  local resp status body rc
  resp="$(curl -sS -X GET -w '\n%{http_code}' "$url")"; rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "❌ curl error (exit=$rc) GET $url"
    return 2
  fi

  status="${resp##*$'\n'}"
  body="${resp%$'\n'$status}"

  if [[ "$status" == 2* || "$status" == "200" ]]; then
    # Respuesta OK (no validamos JSON estrictamente aquí)
    echo "OK smoke_tecnico_orden_detalle"
    return 0
  fi

  if [[ "$status" == "404" ]]; then
    [[ -n "${body// }" ]] && echo "$body"
    echo "HTTP status: 404"
    return 1
  fi

  # Otros errores: mostrar body y logs para diagnosticar
  [[ -n "${body// }" ]] && echo "$body"
  echo "HTTP status: $status"
  echo "== recent api logs (30s) =="
  docker compose logs --since=30s api || true
  echo "== end logs =="
  return 3
}

main() {
  local default_code="INS-000001"
  echo "== ${API}/tecnico/ordenes/${default_code}"

  # 1) Intento con el código fijo histórico
  if try_code "$default_code"; then
    exit 0
  fi

  # 2) Buscar un INS real en DB (preferir sin ~old, si no hay cae a ~old)
  echo "-- buscando un código real de tipo INS en DB…"
  REAL_CODE="$(${PSQL} -c "
WITH c1 AS (
  SELECT codigo FROM public.ordenes
  WHERE tipo='INS' AND codigo NOT LIKE '%~old%'
  ORDER BY created_at DESC
  LIMIT 1
),
c2 AS (
  SELECT codigo FROM public.ordenes
  WHERE tipo='INS' AND codigo LIKE '%~old%'
  ORDER BY created_at DESC
  LIMIT 1
)
SELECT codigo FROM c1
UNION ALL
SELECT codigo FROM c2
LIMIT 1;
")"

  if [[ -z "${REAL_CODE// }" ]]; then
    echo "❌ No se encontraron órdenes de tipo INS en la base de datos."
    exit 1
  fi

  if try_code "$REAL_CODE"; then
    exit 0
  fi

  echo "❌ No se pudo obtener el detalle técnico de la orden."
  exit 1
}

main "$@"
