#!/usr/bin/env bash
# script/smoke_jobs.sh
set -euo pipefail

echo "=== 🧪 smoke_jobs ==="
API="${API:-http://localhost:3000/v1}"
echo "API=${API}"

PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q -At"

json_ok() { jq -e . >/dev/null 2>&1 || { echo "⚠️  respuesta no es JSON válido"; return 1; }; }

# --- Preflight: deduplicar códigos de órdenes de forma idempotente ---
# Solo renombra las filas duplicadas (no toca la 1ª aparición),
# y nunca vuelve a tocar lo ya renombrado (~old-#).
preflight_free_order_codes() {
  ${PSQL} <<'SQL'
WITH base_codes AS (
  SELECT unnest(ARRAY[
    'INS-000001','MAN-000001','COR-000001','REC-000001',
    'BAJ-000001','TRA-000001','CMB-000001','RCT-000001'
  ]) AS codigo
),
candidatas AS (
  -- Considera solo códigos base y que aún NO tengan sufijo ~old
  SELECT o.id, o.codigo
  FROM public.ordenes o
  JOIN base_codes b ON o.codigo = b.codigo
  WHERE o.codigo NOT LIKE '%~old%'
),
ranked AS (
  SELECT id, codigo,
         ROW_NUMBER() OVER (PARTITION BY codigo ORDER BY id) AS rn
  FROM candidatas
),
to_fix AS (
  -- Solo las repeticiones (2ª, 3ª, ...) se renombran
  SELECT id, codigo, rn FROM ranked WHERE rn > 1
)
UPDATE public.ordenes o
SET codigo = o.codigo || '~old-' || t.rn::text
FROM to_fix t
WHERE o.id = t.id;
SQL
}

# curl que falla en 4xx/5xx y muestra info útil
call() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"

  local resp status body code
  if [[ -n "$data" ]]; then
    set +e
    resp="$(curl -sS -X "$method" -H "Content-Type: application/json" -w '\n%{http_code}' --data "$data" "$url")"
    code=$?
    set -e
  else
    set +e
    resp="$(curl -sS -X "$method" -w '\n%{http_code}' "$url")"
    code=$?
    set -e
  fi
  if [[ $code -ne 0 ]]; then
    echo "❌ curl error (exit=$code) $method $url"
    exit $code
  fi
  status="${resp##*$'\n'}"
  body="${resp%$'\n'$status}"

  if [[ "$status" != 2* && "$status" != 201 && "$status" != 204 ]]; then
    [[ -n "${body// }" ]] && echo "$body"
    echo "HTTP status: $status"
    echo "== recent api logs (30s) =="
    docker compose logs --since=30s api || true
    echo "== end logs =="
    exit 1
  fi

  # Best effort: validar JSON si hay body
  if [[ -n "${body// }" ]]; then
    echo "$body" | json_ok || true
  fi
}

main() {
  preflight_free_order_codes

  echo
  echo "-- POST /jobs/simular-cortes"
  call POST "${API}/jobs/simular-cortes" '{}'

  echo
  echo "-- POST /jobs/simular-reconexiones"
  call POST "${API}/jobs/simular-reconexiones" '{}'

  echo
  echo "OK smoke_jobs"
}
main "$@"
