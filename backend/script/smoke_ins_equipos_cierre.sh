#!/usr/bin/env bash
set -euo pipefail

# ================== Config ==================
API=${API:-http://127.0.0.1:3000}
KEY=${KEY:-superdev}
TEC=${TEC:-6}
TIPO=${TIPO:-ONT}
SER=${SER:-ONT-ABC-001}
# ===========================================

echo "== Preparación: elegir INS abierta (o la más reciente) =="
CODE=$(docker compose exec -T db sh -lc \
"psql -At -U ispuser -d ispdb -c \"
WITH open_ins AS (
  SELECT codigo FROM ordenes WHERE tipo='INS' AND cerrada_at IS NULL
  ORDER BY created_at DESC, codigo DESC LIMIT 1
)
SELECT COALESCE(
  (SELECT codigo FROM open_ins),
  (SELECT codigo FROM ordenes WHERE tipo='INS' ORDER BY created_at DESC, codigo DESC LIMIT 1)
);\"")
CODE=$(echo "$CODE" | tr -d '\r')
echo "-> Orden objetivo: $CODE"

# --- (Opcional) Pre-cargar 1 unidad al TEC-$TEC del material mapeado a $TIPO ---
echo "== Preload opcional de stock (1 und) al TEC-$TEC para $TIPO =="
# (Sin DO $$ para evitar problemas de quoting)
docker compose exec -T db sh -lc "
psql -U ispuser -d ispdb -v ON_ERROR_STOP=0 -c \"
SELECT public.fn_mov_simple('ingreso', a.id, c.material_id, 1,
       '[setup] preload TEC-${TEC} ${TIPO}')
FROM almacenes a
JOIN catalogo_equipos_material c ON c.equipo_tipo='${TIPO}'
WHERE a.tecnico_id=${TEC}
LIMIT 1;
\"" >/dev/null || true

reabrir() {
  docker compose exec -T db sh -lc "
  psql -U ispuser -d ispdb -c \"
  UPDATE ordenes
     SET estado='en_proceso', cerrada_at=NULL
   WHERE codigo='${CODE}';
  \" >/dev/null"
}

# ================== Camino A ==================
echo "== Camino A: asignar -> cerrar; reabrir; retirar -> cerrar =="
reabrir
curl -s -H "x-api-key: $KEY" -X PUT "$API/v1/ordenes/$CODE/cerrar" \
  -H 'Content-Type: application/json' \
  -d "{\"tecnicoIdNum\":$TEC,\"payload_cierre\":{\"obs\":\"asignar $TIPO\"},\"equipos\":[{\"equipo_tipo\":\"$TIPO\",\"serial\":\"$SER\",\"accion\":\"asignar\"}]}" \
  | jq -r '.estado,"_idempotent=" + (._idempotent|tostring)'

reabrir
curl -s -H "x-api-key: $KEY" -X PUT "$API/v1/ordenes/$CODE/cerrar" \
  -H 'Content-Type: application/json' \
  -d "{\"tecnicoIdNum\":$TEC,\"payload_cierre\":{\"obs\":\"retirar $TIPO\"},\"equipos\":[{\"equipo_tipo\":\"$TIPO\",\"serial\":\"$SER\",\"accion\":\"retirar\"}]}" \
  | jq -r '.estado,"_idempotent=" + (._idempotent|tostring)'

# ================== Camino B ==================
echo "== Camino B: asignar + retirar en un solo body (reabrimos antes) =="
reabrir
curl -s -H "x-api-key: $KEY" -X PUT "$API/v1/ordenes/$CODE/cerrar" \
  -H 'Content-Type: application/json' \
  -d "{\"tecnicoIdNum\":$TEC,\"payload_cierre\":{\"obs\":\"asignar + retirar\"},\"equipos\":[{\"equipo_tipo\":\"$TIPO\",\"serial\":\"$SER\",\"accion\":\"asignar\"},{\"equipo_tipo\":\"$TIPO\",\"serial\":\"$SER\",\"accion\":\"retirar\"}]}" \
  | jq -r '.estado,"_idempotent=" + (._idempotent|tostring)'

# ================== Camino C ==================
echo "== Camino C: mantener (no debe generar movimientos) =="
reabrir
curl -s -H "x-api-key: $KEY" -X PUT "$API/v1/ordenes/$CODE/cerrar" \
  -H 'Content-Type: application/json' \
  -d "{\"tecnicoIdNum\":$TEC,\"payload_cierre\":{\"obs\":\"mantener $TIPO\"},\"equipos\":[{\"equipo_tipo\":\"$TIPO\",\"serial\":\"$SER\",\"accion\":\"mantener\"}]}" \
  | jq -r '.estado,"_idempotent=" + (._idempotent|tostring)'

# ================== Verificaciones (output) ==================
echo "== Verificaciones =="
docker compose exec -T db sh -lc "
psql -U ispuser -d ispdb -x -c \"
SELECT oe.equipo_tipo, oe.serial, oe.accion, oe.aplicado
FROM orden_equipos oe
JOIN ordenes o ON o.id=oe.orden_id
WHERE o.codigo='${CODE}' AND oe.serial='${SER}'
ORDER BY oe.accion;
\"
"

docker compose exec -T db sh -lc "
psql -U ispuser -d ispdb -x -c \"
SELECT tipo, material_id, cantidad, from_almacen_id, to_almacen_id, nota, fecha
FROM movimientos
WHERE nota ILIKE '%orden ${CODE}%${SER}%'
ORDER BY fecha ASC;
\"
"

# ================== Aserciones duras ==================
# (Recorta espacios y CRLF por si acaso)
CNT_EQUIPOS=$(docker compose exec -T db sh -lc "
psql -At -U ispuser -d ispdb -c \"
SELECT COUNT(*) FROM orden_equipos oe
JOIN ordenes o ON o.id=oe.orden_id
WHERE o.codigo='${CODE}' AND oe.serial='${SER}';
\"" | tr -d '[:space:]')
if [ "$CNT_EQUIPOS" != "3" ]; then
  echo "ERROR: esperábamos 3 filas en orden_equipos (asignar, retirar, mantener) y hay $CNT_EQUIPOS"
  exit 1
fi

CNT_MOVS=$(docker compose exec -T db sh -lc "
psql -At -U ispuser -d ispdb -c \"
SELECT COUNT(*) FROM movimientos
WHERE nota ILIKE '%orden ${CODE}%${SER}%';
\"" | tr -d '[:space:]')
if [ "$CNT_MOVS" != "2" ]; then
  echo "ERROR: esperábamos 2 movimientos (egreso+ingreso) y hay $CNT_MOVS"
  exit 1
fi

echo "Asserts OK ✅"
echo "Listo ✅"
