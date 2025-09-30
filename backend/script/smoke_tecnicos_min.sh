#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API_V1="$API_BASE/v1"

# --- helpers ---
wait_api() {
  local url1="$API_V1/health"
  local url2="$API_BASE/health"
  echo "⏳ Esperando API (probando /v1/health y /health sobre $API_BASE) ..."
  for i in {1..60}; do
    if curl -fsS "$url1" >/dev/null 2>&1 || curl -fsS "$url2" >/dev/null 2>&1; then
      echo "✅ API OK en $url1"
      return 0
    fi
    sleep 1
  done
  echo "❌ API no respondió a tiempo"; exit 1
}

wait_pg() {
  local host="$1" port="$2" user="$3" db="$4"
  echo "⏳ Probando conexión a Postgres..."
  for i in {1..60}; do
    if pg_isready -h "$host" -p "$port" -U "$user" -d "$db" >/dev/null 2>&1; then
      echo "✅ Postgres OK via $host:$port"
      return 0
    fi
    sleep 1
  done
  echo "❌ Postgres no respondió a tiempo"; exit 1
}

# --- main ---
echo "=== 🛠️  Smoke Técnicos (mínimo) v13 ==="

wait_api

# Credenciales/host de BD (compat local con docker compose)
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5433}"
PGUSER="${PGUSER:-ispuser}"
PGDATABASE="${PGDATABASE:-ispdb}"
export PGPASSWORD="${PGPASSWORD:-$(docker compose exec -T db printenv POSTGRES_PASSWORD)}"

if [[ -n "${PGPASSWORD:-}" ]]; then
  echo "🔑 Usando contraseña Postgres desde \$PGPASSWORD del entorno."
else
  echo "❌ No se pudo obtener PGPASSWORD"; exit 1
fi

wait_pg "$PGHOST" "$PGPORT" "$PGUSER" "$PGDATABASE"

echo "🔧 Bootstrap BD (idempotente + compat cierre) vía archivo .sql…"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -f script/bootstrap_tecnicos.sql

# (Opcional) Pequeña verificación mínima para asegurar que no se cayó nada clave
echo "🔎 Verificación mínima de estructuras clave…"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -X -A -t -q <<'SQL'
-- kardex existe?
SELECT 'kardex_ok'
WHERE EXISTS (
  SELECT 1 FROM information_schema.views
  WHERE table_schema='public' AND table_name='kardex'
);
-- trigger en movimientos?
SELECT 'trg_movs_ok'
WHERE EXISTS (
  SELECT 1 FROM pg_trigger
  WHERE tgrelid='public.movimientos'::regclass
    AND tgname='trg_movs_sync_stock'
    AND NOT tgisinternal
);
SQL

echo "🎉 Smoke Técnicos mínimo OK"
