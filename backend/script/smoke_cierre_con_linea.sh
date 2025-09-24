#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config
# =========================
API_BASE="${API_BASE:-http://localhost:3000}"
TEC_CODE="${TEC_CODE:-TEC-0001}"
MAT_CODE="${MAT_CODE:-MAT-0001}"
OID_CODE="${OID_CODE:-MAN-000001}"

say()  { printf '%s\n' "$*"; }
hr()   { printf '%0.s-' {1..100}; echo; }
fail() { say "✗ $*"; exit 1; }

# Wrapper a psql
psql_db() {
  docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 "$@"
}

# =========================
# [0] Health
# =========================
say "[0] Health"
curl -fsS "$API_BASE/v1/health" | jq .
hr

# =========================
# [1] Resolver IDs por código
# =========================
say "[1] Resolver IDs por código (técnico, material, orden)"
readarray -t RES <<<"$(psql_db -Atc "
with t as (select id as tec_id from tecnicos  where codigo='$TEC_CODE'),
     m as (select id as mat_id from materiales where codigo='$MAT_CODE'),
     o as (select id as oid_db from ordenes    where codigo='$OID_CODE')
select coalesce((select tec_id from t)::text,''),
       coalesce((select mat_id from m)::text,''),
       coalesce((select oid_db from o)::text,'');
")"

IFS='|' read -r TECID MATID OID_DB <<<"${RES[0]:-||}"
[[ -n "$TECID" && -n "$MATID" && -n "$OID_DB" ]] || fail "No se pudieron resolver IDs (TECID/MATID/OID_DB)."

say "TECID=$TECID  MATID=$MATID  OID_DB=$OID_DB (code=$OID_CODE)"

# Detectar nombre real de la tabla de líneas (o alias de compat)
TABLE_OM="$(psql_db -Atc "
select case
  when to_regclass('public.ordenes_materiales') is not null then 'ordenes_materiales'
  when to_regclass('public.orden_materiales')  is not null then 'orden_materiales'
  when to_regclass('public.orden_material')    is not null then 'orden_material'
  else null end;
")"
[[ -n "$TABLE_OM" ]] || fail "No existe tabla/vista de líneas (aplica sql/007_ordenes_materiales_compat.sql)."
say "→ Tabla de líneas detectada: $TABLE_OM"
hr

# =========================
# [2] Upserts (inv_tecnico + línea en orden)
# =========================
say "[2] Upsert stock del técnico (>=2 uds) + Upsert línea en orden (precio_unitario)"
# Variables para psql
psql_db -v TECID="$TECID" -v MATID="$MATID" -v OID_DB="$OID_DB" -v TABLE_OM="$TABLE_OM" <<'SQL'
-- Garantiza la extensión (por si un entorno nuevo)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Garantiza inv_tecnico (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inv_tecnico'
  ) THEN
    CREATE TABLE inv_tecnico (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      tecnico_id  UUID        NOT NULL,
      material_id INTEGER     NOT NULL,
      cantidad    INTEGER     NOT NULL DEFAULT 0,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ
    );
    CREATE UNIQUE INDEX ux_inv_tecnico_tecmat ON inv_tecnico(tecnico_id, material_id);
  END IF;
END$$;

-- Stock del técnico (al menos 2 uds)
INSERT INTO inv_tecnico(id, tecnico_id, material_id, cantidad, created_at, updated_at)
VALUES (gen_random_uuid(), :'TECID'::uuid, :'MATID'::int, 2, now(), now())
ON CONFLICT (tecnico_id, material_id)
DO UPDATE SET cantidad = GREATEST(inv_tecnico.cantidad, 2), updated_at = now();

-- 2.1) UPDATE de la línea si ya existe
SELECT format(
  'UPDATE %I
     SET cantidad = cantidad + 1,
         precio_unitario = 1200
   WHERE orden_id = %L::uuid
     AND material_id = %s::int;',
  :'TABLE_OM', :'OID_DB', :'MATID'
) \gexec

-- 2.2) INSERT si no existía (sin requerir índice único)
SELECT format(
  'INSERT INTO %I (orden_id, material_id, cantidad, precio_unitario)
   SELECT %L::uuid, %s::int, 1, 1200
   WHERE NOT EXISTS (
     SELECT 1 FROM %I WHERE orden_id = %L::uuid AND material_id = %s::int
   );',
  :'TABLE_OM', :'OID_DB', :'MATID',
  :'TABLE_OM', :'OID_DB', :'MATID'
) \gexec
SQL
say "✓ upserts OK"
hr

# =========================
# [3] Verificación totales
# =========================
say "[3] Verificación de totales en DB (muestra conteo y totales estimados)"
psql_db -v MATID="$MATID" -v OID_DB="$OID_DB" -At <<SQL | tee /dev/stderr >/dev/null
WITH x AS (
  SELECT cantidad::numeric AS qty,
         COALESCE(precio_unitario::numeric,0) AS pu,
         (COALESCE(precio_unitario::numeric,0) * cantidad::numeric) AS total
  FROM $TABLE_OM
  WHERE orden_id = :'OID_DB'::uuid AND material_id = :'MATID'::int
)
SELECT count(*), sum(qty), min(pu), sum(total) FROM x;
SQL
say "✓ Done"
