#!/usr/bin/env bash
set -euo pipefail

API=${API:-http://127.0.0.1:3000}
DB=${DB:-postgresql://postgres:postgres@127.0.0.1:5432/isp}
MAT=${MAT:-3}
ALM_PRI=${ALM_PRI:-b96c5ba1-9820-43fa-b9cb-b33e62a0db6b}
ALM_TEC=${ALM_TEC:-a8e5e907-9a7c-4aa7-b80b-f0ad2c7f3692}
TEC_ID=${TEC_ID:-c1f2dd81-8f1c-477c-b7cd-580dd13916d3}

echo "== Versión API y health =="
curl -s "${API}/v1/health" | jq .

echo "== Flags de auditoría =="
echo "LOG_LEVEL=${LOG_LEVEL:-}" ; echo "NODE_ENV=${NODE_ENV:-}" ; echo "TZ=${TZ:-}"

echo "== MinIO status (opcional)=="
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'isp-(minio|api|db)' || true

echo "== SQL snapshots principales (inventario y vistas) =="
psql "${DB}" -v "ON_ERROR_STOP=1" <<'SQL'
\timing on
-- Stock almacen vs inv_tecnico (material puntual)
SELECT a.id AS almacen_id, a.tipo, a.tecnico_id,
       sa.material_id, sa.cantidad AS stock_almacen,
       it.cantidad AS inv_tecnico
FROM   almacenes a
LEFT JOIN stock_almacen sa
  ON sa.almacen_id=a.id AND sa.material_id=:MAT
LEFT JOIN inv_tecnico it
  ON it.tecnico_id=a.tecnico_id AND it.material_id=:MAT
WHERE a.id IN (:'ALM_PRI', :'ALM_TEC')
ORDER BY a.tipo;

-- Desviaciones
SELECT * FROM v_desviacion_inv_tecnico WHERE material_id=:MAT AND tecnico_id=:TEC_ID ORDER BY material_id;

-- Últimos movimientos (kardex)
SELECT * FROM v_kardex WHERE material_id=:MAT ORDER BY created_at DESC LIMIT 10;

-- Ordenes cerradas recientes con consolidación
SELECT codigo, estado, cerrada_at FROM ordenes
WHERE estado='cerrada' AND codigo LIKE 'MAN-%'
ORDER BY cerrada_at DESC LIMIT 5;

-- OM detallado de la última MAN cerrada
WITH ult AS (
  SELECT id,codigo FROM ordenes WHERE estado='cerrada' AND codigo LIKE 'MAN-%' ORDER BY cerrada_at DESC LIMIT 1
)
SELECT om.id,om.orden_id,om.material_id,om.cantidad,om.descontado
FROM orden_materiales om
JOIN ult u ON u.id=om.orden_id
ORDER BY om.material_id, om.id;

SQL

echo "== Repro rápido bug consolidación (opcional) =="
cat > script/repro_consolidacion.sh <<'REPRO'
#!/usr/bin/env bash
set -euo pipefail
API=${API:-http://127.0.0.1:3000}
TEC_ID=${TEC_ID:-c1f2dd81-8f1c-477c-b7cd-580dd13916d3}

COD="MAN-$(date +%y%m%d%H%M%S)-DUPCHK"
echo "→ crear MAN ${COD}"
curl -s -X POST "${API}/v1/ordenes/manual" -H 'content-type: application/json' \
  -d '{"codigo":"'"${COD}"'","tipo":"MAN"}' >/dev/null || true

echo "→ asignar"
curl -s -X POST "${API}/v1/agenda/ordenes/${COD}/asignar" -H 'content-type: application/json' \
  -d '{"fecha":"'"$(date +%F)"'","turno":"am","tecnicoId":"'"${TEC_ID}"'"}' > /dev/null

echo "→ iniciar"
curl -s -X POST "${API}/v1/tecnicos/${TEC_ID}/ordenes/codigo/${COD}/iniciar" -H 'content-type: application/json' -d '{}' > /dev/null

echo "→ cerrar con materiales duplicados (1 + 2)"
BODY='{"materiales":[{"materialIdInt":3,"cantidad":1},{"materialIdInt":3,"cantidad":2}]}'
curl -s -X POST "${API}/v1/tecnicos/${TEC_ID}/ordenes/codigo/${COD}/cerrar" \
  -H 'content-type: application/json' -d "${BODY}" | jq .

echo "→ sanity espejo (diff debe 0)"
psql "${DB}" -c "SELECT * FROM v_desviacion_inv_tecnico WHERE diff<>0 ORDER BY tecnico_id,material_id"
REPRO
chmod +x script/repro_consolidacion.sh
echo "Para reproducir: API=${API} DB=${DB} bash script/repro_consolidacion.sh"
