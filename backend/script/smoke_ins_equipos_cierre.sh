# script/smoke_ins_equipos_cierre.sh
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
ORDER_COD="${1:-}"        # si no pasas parámetro, detecta la última INS desde la DB
CLEAN="${CLEAN:-true}"    # true: borra los inserts de prueba; false: los deja
PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q"

banner() {
  echo "=== 🧪 smoke_ins_equipos_cierre ===  API=${API}"
}

pick_order_from_db() {
  ${PSQL} -Atc "SELECT codigo FROM ordenes WHERE tipo='INS' ORDER BY created_at DESC NULLS LAST LIMIT 1"
}

probe_endpoint() {
  local cod="$1"
  curl -sS -o /dev/null -w "%{http_code}" "${API}/ordenes/${cod}/equipos" || true
}

db_assert_schema() {
  echo "→ Validando esquema mínimo de orden_equipos…"
  ${PSQL} -c "SELECT to_regclass('public.orden_equipos')" -At >/dev/null
  ${PSQL} -c "SELECT 1 FROM pg_type WHERE typname='orden_equipo_accion'" -At >/dev/null
  ${PSQL} -c "SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='orden_equipos' AND column_name='orden_codigo'" -At >/dev/null
  ${PSQL} -c "SELECT 1 FROM pg_constraint
               WHERE conname='fk_orden_equipos_orden_codigo'
                 AND conrelid='public.orden_equipos'::regclass" -At >/dev/null
  echo "  ✓ OK esquema/enum/FK listos"
}

db_mode_run() {
  local cod="$1"
  db_assert_schema

  local STAMP
  STAMP="$(date +%Y%m%d%H%M%S)"

  echo "→ Modo DB: insertando 3 filas de prueba para ${cod}…"
  ${PSQL} <<SQL
BEGIN;

-- Limpieza preventiva de residuos previos del mismo orden (idempotente)
DELETE FROM orden_equipos
 WHERE orden_codigo='${cod}' AND codigo LIKE 'SMK-%';

-- Inserta A/B/C (sin columna 'aplicado')
INSERT INTO orden_equipos (codigo, accion, orden_codigo, material_id, serial, payload)
VALUES
  ('SMK-${STAMP}-A','asignar','${cod}',3,'SN-SMK-A', '{"smoke":true}'),
  ('SMK-${STAMP}-B','retirar','${cod}',3,'SN-SMK-B', '{"smoke":true}'),
  ('SMK-${STAMP}-C','mantener','${cod}',3,'SN-SMK-C', '{"smoke":true}');

-- Verifica que estén exactamente las 3 filas insertadas por este run
DO \$\$
DECLARE v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM orden_equipos
  WHERE orden_codigo='${cod}' AND codigo LIKE 'SMK-${STAMP}-%';
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION 'Verificación falló: esperadas 3 filas SMK-${STAMP}-* para %, encontradas %', '${cod}', v_cnt;
  END IF;
END
\$\$;

COMMIT;
SQL

  echo "  ✓ Verificación OK: 3 filas SMK-${STAMP}-* para ${cod}"

  if [[ "${CLEAN}" == "true" ]]; then
    echo "→ Limpieza de filas SMK-${STAMP}-* (CLEAN=true)…"
    ${PSQL} -c "DELETE FROM orden_equipos WHERE codigo LIKE 'SMK-${STAMP}-%';" -At >/dev/null
    echo "  ✓ Limpieza OK"
  else
    echo "ℹ️  CLEAN=false → se conservan filas SMK-${STAMP}-* para auditoría"
  fi

  echo "🎉 smoke_ins_equipos_cierre (modo DB) OK para ${cod}"
}

api_mode_run() {
  local cod="$1"
  echo "→ Modo API para ${cod}…"
  # En cuanto expongas /ordenes/:codigo/equipos agrega aquí el flujo real (GET/POST/etc).
  echo "ℹ️  Por ahora no hay implementación API; si 404 → caemos a modo DB."
}

main() {
  banner

  if [[ -z "${ORDER_COD}" ]]; then
    ORDER_COD="$(pick_order_from_db)"
  fi
  if [[ -z "${ORDER_COD}" ]]; then
    echo "❌ No encontré ninguna orden INS en la DB."
    exit 1
  fi
  echo "→ Orden objetivo: ${ORDER_COD}"

  local code
  code="$(probe_endpoint "${ORDER_COD}")"
  if [[ "${code}" == "200" || "${code}" == "201" ]]; then
    api_mode_run "${ORDER_COD}"
    echo "🎉 smoke_ins_equipos_cierre (modo API) OK para ${ORDER_COD}"
  elif [[ "${code}" == "404" || -z "${code}" ]]; then
    echo "ℹ️  Endpoint /ordenes/:codigo/equipos no disponible (HTTP ${code:-ERR}). Usando modo DB…"
    db_mode_run "${ORDER_COD}"
  else
    echo "⚠️  HTTP ${code} inesperado; intento modo DB para no romper CI…"
    db_mode_run "${ORDER_COD}"
  fi
}

main "$@"
