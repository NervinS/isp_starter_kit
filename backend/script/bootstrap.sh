#!/usr/bin/env bash
set -euo pipefail

# -------- Config ----------
DB_HOST="${DB_HOST:-127.0.0.1}"   # host local por defecto
DB_PORT="${DB_PORT:-5433}"        # en docker-compose local mapeaste 5433->5432
DB_USER="${DB_USER:-ispuser}"
DB_PASS="${DB_PASS:-isppass}"
DB_NAME="${DB_NAME:-ispdb}"

SQL_FILE="${SQL_FILE:-script/bootstrap_db_v2.sql}"
SEED_MIN="${SEED_MIN:-0}"         # 1 para sembrar técnico/material mínimos

# -------- Helpers ----------
msg() { printf "\033[1;36m%s\033[0m\n" "$*"; }
err() { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Falta '$1'. Instálalo (ej. sudo apt-get install -y postgresql-client)"; exit 1;
  }
}

wait_pg() {
  msg "⏳ Esperando Postgres en ${DB_HOST}:${DB_PORT}…"
  for i in {1..60}; do
    if PGPASSWORD="$DB_PASS" pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; then
      msg "✅ Postgres listo"
      return 0
    fi
    sleep 1
  done
  err "❌ Postgres no respondió a tiempo"; exit 1
}

psql_run() {
  PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 "$@"
}

seed_minimal() {
  msg "🌱 Sembrando datos mínimos (opcional)…"
  psql_run <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.tecnicos WHERE codigo='TEC-0006') THEN
    INSERT INTO public.tecnicos (codigo, nombre, activo) VALUES ('TEC-0006','Tecnico CI', true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.materiales WHERE codigo='MAT-RJ45') THEN
    INSERT INTO public.materiales (codigo, nombre, unidad, activo) VALUES ('MAT-RJ45','Conector RJ45','UND', true);
  END IF;
END$$;
SQL
}

# -------- Main ----------
need psql
need pg_isready
[ -f "$SQL_FILE" ] || { err "No se encuentra ${SQL_FILE} (corre desde 'backend/')"; exit 1; }

msg "🔧 Parámetros:"
echo "  DB_HOST=${DB_HOST}"
echo "  DB_PORT=${DB_PORT}"
echo "  DB_USER=${DB_USER}"
echo "  DB_NAME=${DB_NAME}"
echo "  SQL_FILE=${SQL_FILE}"
echo "  SEED_MIN=${SEED_MIN}"

wait_pg

msg "🗃️  Versión de Postgres:"
psql_run -c "SELECT version();"

msg "📜 Aplicando ${SQL_FILE} (idempotente)…"
psql_run -f "$SQL_FILE"

if [ "$SEED_MIN" = "1" ]; then
  seed_minimal
fi

msg "🎉 Bootstrap OK"
