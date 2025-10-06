#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:3000}"
KEY="${KEY:-superdev}"

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-ispuser}"
DB_NAME="${DB_NAME:-ispdb}"
DB_PASS="${DB_PASS:-}"   # opcional si usas contenedor
USE_DOCKER_DB="${USE_DOCKER_DB:-1}"  # 1 -> psql dentro del contenedor "db"
SEED_MAIN_QTY="${SEED_MAIN_QTY:-10}"

export PGPASSWORD="${DB_PASS}"

SQL_FILE="${SQL_FILE:-script/bootstrap_db_v2.sql}"

# Lista de migraciones conocidas (ajusta si agregas nuevas)
MIGRATION_FILES=(
  "script/migration_20251001_ventas_ordenes.sql"
  "script/migration_20251001_ventas_evidencias.sql"
  "script/migration_20251001_ventas_pagos_idem.sql"
  "script/migration_20251001_ordenes_tipos_all.sql"
  "script/migration_20251001_ordenes_datos_tecnicos.sql"
  "script/migration_20251001_ordenes_evidencias_tbl.sql"
  "script/migration_20251001_ordenes_pdf.sql"
  "script/migration_20251001_equipos.sql"
  "script/migration_20251001_materiales_basics.sql"
  "script/migration_20251001_materiales_id_identity.sql"
  "script/migration_20251001_materiales_id_seq_fix.sql"
  "script/migration_20251001_almacenes_seed.sql"
  "script/migration_20251001_almacenes_backfill_tecnicos.sql"
  "script/migration_20251001_ordenes_ins_unica_activa.sql"
  "script/migration_20251001_catalogo_motivos_anulacion.sql"
  "script/migration_20251001_ordenes_motivo_anulacion.sql"
  "script/migration_20251001_tecnicos_codigo.sql"
  "script/migration_20251001_tecnicos_basics.sql"
  "script/migration_20251001_tecnicos_id_identity.sql"
  "script/migration_20251001_tecnicos_id_seq_fix.sql"
  "script/migration_20251002_inventario_core.sql"
  "script/migration_20251002_stock_almacen_timestamps.sql"
  "script/migration_20251002_movimientos_tipo_traslado.sql"
  "script/migration_20251002_inventario_funcs_force.sql"
  "script/migration_20251002_inventario_funcs.sql"
  "script/migration_20251002_kardex_view.sql"
)

echo "🔧 Parámetros:
  DB_HOST=${DB_HOST}
  DB_PORT=${DB_PORT}
  DB_USER=${DB_USER}
  DB_NAME=${DB_NAME}
  SQL_FILE=${SQL_FILE}
  USE_DOCKER_DB=${USE_DOCKER_DB}
  SEED_MAIN_QTY=${SEED_MAIN_QTY}"

# --- Helpers de psql ---
PSQL_ARGS=(-v ON_ERROR_STOP=1 --no-password -w)

if [[ "${USE_DOCKER_DB}" == "1" ]]; then
  psql_run()  { docker compose exec -T db psql "${PSQL_ARGS[@]}" -U "${DB_USER}" -d "${DB_NAME}" -c "$1"; }
  psql_file() { docker compose exec -T db psql "${PSQL_ARGS[@]}" -U "${DB_USER}" -d "${DB_NAME}" < "$1"; }
  psql_heredoc() { docker compose exec -T db psql "${PSQL_ARGS[@]}" -U "${DB_USER}" -d "${DB_NAME}"; }
  wait_pg() {
    echo "⏳ Esperando Postgres (contenedor)…"
    for i in {1..60}; do
      if docker compose exec -T db pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
        echo "✅ Postgres listo (contenedor)"; return 0
      fi
      sleep 1
    done
    echo "❌ No respondió pg dentro del contenedor" >&2; exit 1
  }
else
  PSQL_CONN=(psql "${PSQL_ARGS[@]}" \
    "host=${DB_HOST} port=${DB_PORT} user=${DB_USER} dbname=${DB_NAME} sslmode=disable connect_timeout=2")
  psql_run()  { "${PSQL_CONN[@]}" -c "$1"; }
  psql_file() { "${PSQL_CONN[@]}" < "$1"; }
  psql_heredoc() { "${PSQL_CONN[@]}"; }
  wait_pg() {
    echo "⏳ Esperando Postgres en ${DB_HOST}:${DB_PORT}…"
    for i in {1..60}; do
      if "${PSQL_CONN[@]}" -c "select 1" >/dev/null 2>&1; then
        echo "✅ Postgres listo"; return 0
      fi
      sleep 1
    done
    echo "❌ No se pudo conectar a Postgres en ${DB_HOST}:${DB_PORT}" >&2
    exit 1
  }
fi

wait_pg

echo "🗃️  Versión de Postgres:"
psql_run "SELECT version();"

# ===== Bootstrap principal =====
if [[ -f "${SQL_FILE}" ]]; then
  echo "📜 Aplicando ${SQL_FILE} (idempotente)…"
  psql_file "${SQL_FILE}"
else
  echo "⚠️  No existe ${SQL_FILE}, continúo…"
fi

for f in "${MIGRATION_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo "📜 Aplicando ${f} (idempotente)…"
    set +e
    psql_file "$f"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      echo "⚠️  Falló ${f} (continuo por ser idempotente)."
    fi
  fi
done

echo "🎉 Bootstrap OK"

# ===== Seeding: garantizar stock mínimo en MAIN para TODOS los materiales =====
echo "🌱 Seeding en MAIN para TODOS los materiales (mínimo ${SEED_MAIN_QTY})…"
psql_heredoc <<'SQL'
WITH main AS (
  SELECT id FROM public.almacenes WHERE codigo='MAIN' LIMIT 1
),
saldos AS (
  SELECT mat.id AS material_id,
         COALESCE(SUM(
           CASE
             WHEN m.tipo IN ('ingreso','ajuste') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
             WHEN m.tipo = 'egreso'               AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
             WHEN m.tipo = 'transferencia'        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
             WHEN m.tipo = 'transferencia'        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
             ELSE 0
           END
         ),0) AS s
  FROM public.materiales mat
  LEFT JOIN public.movimientos m
         ON m.material_id = mat.id
        AND (m.almacen_destino_id = (SELECT id FROM main)
          OR m.almacen_origen_id  = (SELECT id FROM main))
  GROUP BY mat.id
),
to_ins AS (
  SELECT (SELECT id FROM main) AS mid,
         material_id,
         GREATEST(:'SEED_MAIN_QTY'::int - s, 0) AS falta
  FROM saldos
  WHERE GREATEST(:'SEED_MAIN_QTY'::int - s, 0) > 0
)
INSERT INTO public.movimientos (tipo, almacen_origen_id, almacen_destino_id, material_id, cantidad, nota)
SELECT 'ingreso', NULL, mid, material_id, falta, 'seed MAIN bootstrap'
FROM to_ins;
SQL

echo "✅ MAIN quedó con al menos ${SEED_MAIN_QTY} unidades por material"
