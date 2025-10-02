#!/usr/bin/env bash
set -euo pipefail

# -------- Config ----------
DB_HOST="${DB_HOST:-127.0.0.1}"   # host local por defecto
DB_PORT="${DB_PORT:-5433}"        # en docker-compose local mapeaste 5433->5432
DB_USER="${DB_USER:-ispuser}"
DB_PASS="${DB_PASS:-isppass}"
DB_NAME="${DB_NAME:-ispdb}"

SQL_FILE="${SQL_FILE:-script/bootstrap_db_v2.sql}"
# Migraciones específicas (puedes sobreescribirlas por env si quieres)
MIGRATION_FILE_ORDENES="${MIGRATION_FILE_ORDENES:-script/migration_20251001_ventas_ordenes.sql}"
MIGRATION_FILE_EVIDENCIAS="${MIGRATION_FILE_EVIDENCIAS:-script/migration_20251001_ventas_evidencias.sql}"

SEED_MIN="${SEED_MIN:-0}"         # 1 para sembrar técnico/material mínimos

# -------- Helpers ----------
msg()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m%s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

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

apply_sql_file() {
  local file="$1"
  if [ -f "$file" ]; then
    msg "📜 Aplicando ${file} (idempotente)…"
    psql_run -f "$file"
  else
    warn "⚠️  No se encontró ${file} — se omite."
  fi
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
    INSERT INTO public.materiales (codigo, nombre, unidad, activo) VALUES ('MAT-RJ45','Conector RJ45','UND', true)
    ON CONFLICT (codigo) DO NOTHING;
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
echo "  MIGRATION_FILE_ORDENES=${MIGRATION_FILE_ORDENES}"
echo "  MIGRATION_FILE_EVIDENCIAS=${MIGRATION_FILE_EVIDENCIAS}"
echo "  SEED_MIN=${SEED_MIN}"

wait_pg

msg "🗃️  Versión de Postgres:"
psql_run -c "SELECT version();"

# 1) Bootstrap base
apply_sql_file "$SQL_FILE"

# 2) Migraciones (idempotentes) en orden lógico
#   Ventas / ordenes iniciales
apply_sql_file "$MIGRATION_FILE_ORDENES"
apply_sql_file "$MIGRATION_FILE_EVIDENCIAS"
apply_sql_file "script/migration_20251001_ventas_pagos_idem.sql"

#   Ordenes: tipos y tablas auxiliares
apply_sql_file "script/migration_20251001_ordenes_tipos_all.sql"
apply_sql_file "script/migration_20251001_ordenes_datos_tecnicos.sql"
apply_sql_file "script/migration_20251001_ordenes_evidencias_tbl.sql"
apply_sql_file "script/migration_20251001_ordenes_pdf.sql"

#   Equipos / inventario maestro y almacenes (seed + backfill)
apply_sql_file "script/migration_20251001_equipos.sql"
apply_sql_file "script/migration_20251001_materiales_basics.sql"
apply_sql_file "script/migration_20251001_materiales_id_identity.sql"
apply_sql_file "script/migration_20251001_materiales_id_seq_fix.sql"
apply_sql_file "script/migration_20251001_almacenes_seed.sql"
apply_sql_file "script/migration_20251001_almacenes_backfill_tecnicos.sql"

#   Reglas adicionales en ordenes
apply_sql_file "script/migration_20251001_ordenes_ins_unica_activa.sql"
apply_sql_file "script/migration_20251001_catalogo_motivos_anulacion.sql"
apply_sql_file "script/migration_20251001_ordenes_motivo_anulacion.sql"
apply_sql_file "script/migration_20251001_tecnicos_codigo.sql"
apply_sql_file "script/migration_20251001_tecnicos_basics.sql"
apply_sql_file "script/migration_20251001_tecnicos_id_identity.sql"
apply_sql_file "script/migration_20251001_tecnicos_id_seq_fix.sql"

#   Inventario core + vistas
apply_sql_file "script/migration_20251002_inventario_core.sql"
apply_sql_file "script/migration_20251002_stock_almacen_timestamps.sql"
apply_sql_file "script/migration_20251002_movimientos_tipo_traslado.sql"

#   👇 Fuerza limpieza de la función (evita errores de tipo de retorno o "ya existe")
apply_sql_file "script/migration_20251002_inventario_funcs_force.sql"

#   Funciones y kárdex
apply_sql_file "script/migration_20251002_inventario_funcs.sql"
apply_sql_file "script/migration_20251002_kardex_view.sql"

# 3) Seed opcional
if [ "$SEED_MIN" = "1" ]; then
  seed_minimal
fi

msg "🎉 Bootstrap OK"
