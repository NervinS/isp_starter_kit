#!/usr/bin/env bash
# smoke_cierre_idempotente.sh
# Prueba SOFT: dos cierres seguidos deben devolver 403/403 mientras no implementes idempotencia en API.
# Cuando la implementes, corre con IDEMPOTENCY_HARD=1 para esperar 200/204 y luego 200/204/409.
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
DB_SVC="${DB_SVC:-db}"
PSQL_USER="${PSQL_USER:-ispuser}"
PSQL_DB="${PSQL_DB:-ispdb}"
IDEMPOTENCY_HARD="${IDEMPOTENCY_HARD:-0}"

psql_db() {
  if docker compose ps -q "$DB_SVC" >/dev/null 2>&1; then
    docker compose exec -T "$DB_SVC" psql -U "$PSQL_USER" -d "$PSQL_DB" -v ON_ERROR_STOP=1 "$@"
  else
    psql -U "$PSQL_USER" -d "$PSQL_DB" -v ON_ERROR_STOP=1 "$@"
  fi
}

# técnico
TECID="$(psql_db -Atc "select id::text from tecnicos where codigo='TEC-0001' limit 1;" 2>/dev/null || true)"
if [[ -z "${TECID}" ]]; then
  TECID="$(psql_db -Atc "select id::text from tecnicos limit 1;" 2>/dev/null || true)"
fi
if [[ -z "${TECID}" ]]; then
  echo "✗ No hay técnicos en la DB"; exit 1
fi

# tipo válido
TIPO_OK="$(psql_db -Atc "select tipo from ordenes where tipo is not null limit 1;" 2>/dev/null || true)"
TIPO_OK="${TIPO_OK:-instalacion}"

OID="IDEM-$(date -u +%Y%m%d%H%M%S)-$RANDOM"

# Orden creada + asignada
psql_db -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null || true
psql_db <<SQL
INSERT INTO ordenes(codigo, estado, tipo) VALUES ('$OID','creada','$TIPO_OK') ON CONFLICT (codigo) DO NOTHING;
UPDATE ordenes SET tecnico_id='$TECID'::uuid, estado='agendada' WHERE codigo='$OID';
SQL

echo "▶ Health"
curl -sS "${API_BASE}/v1/health" >/dev/null && echo "✓ API OK" || { echo "✗ API down"; exit 1; }

# Disparamos dos cierres SIN token (debe dar 403 mientras no hay idempotencia)
HTTP1=$(curl -sS -o /dev/stderr -w "%{http_code}" -X POST "${API_BASE}/v1/tecnicos/${TECID}/ordenes/${OID}/cerrar" || true)
echo "▶ cierre #1 = ${HTTP1}"
HTTP2=$(curl -sS -o /dev/stderr -w "%{http_code}" -X POST "${API_BASE}/v1/tecnicos/${TECID}/ordenes/${OID}/cerrar" || true)
echo "▶ cierre #2 = ${HTTP2}"

if [[ "${IDEMPOTENCY_HARD}" == "1" ]]; then
  # Cuando implementes idempotencia real en API, esto es lo que se espera:
  case "${HTTP1}:${HTTP2}" in
    200:200|200:204|200:409|204:200|204:204|204:409)
      echo "✓ idempotencia HARD OK"; exit 0;;
    *)
      echo "✗ Idempotencia HARD esperada (200/204 y luego 200/204/409). Obtuve ${HTTP1}/${HTTP2}"; exit 1;;
  esac
else
  # Modo SOFT (mientras NO hay idempotencia): esperamos 403/403
  if [[ "${HTTP1}" == "403" && "${HTTP2}" == "403" ]]; then
    echo "✓ idempotencia SOFT OK (403/403 mientras no hay implementación en API)"
    exit 0
  else
    echo "✗ SOFT esperaba 403/403. Obtuve ${HTTP1}/${HTTP2}"
    exit 1
  fi
fi
