#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:3000/v1"
TEC_ID="c1f2dd81-8f1c-477c-b7cd-580dd13916d3"

psqlc() {
  docker compose exec -T db psql -U ispuser -d ispdb -qAtX -c "$1"
}

echo
echo "==================== 0) Verificación de TRIGGERS e índices ===================="

echo
echo "TRIGGERS orden_materiales:"
psqlc "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='orden_materiales' AND NOT t.tgisinternal ORDER BY 1;"

echo
echo "TRIGGERS inv_tecnico:"
psqlc "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='inv_tecnico' AND NOT t.tgisinternal ORDER BY 1;"

echo
echo "Únicos en inv_tecnico:"
psqlc "SELECT i.relname FROM pg_class t JOIN pg_index ix ON t.oid=ix.indrelid JOIN pg_class i ON i.oid=ix.indexrelid WHERE t.relname='inv_tecnico' AND ix.indisunique ORDER BY 1;"

echo
echo "==================== 1) Flujo MAN end-to-end ===================="

MAN="MAN-$(date +%y%m%d%H%M%S)"
echo
echo "→ MAN=$MAN"

ORD_ID=$(psqlc "
WITH t AS (
  INSERT INTO ordenes (id,codigo,estado,tecnico_id,tipo,usuario_id,agendada_at)
  VALUES (gen_random_uuid(),'$MAN','agendada','$TEC_ID','MAN',
          (SELECT id FROM usuarios ORDER BY created_at DESC LIMIT 1), now())
  RETURNING id
) SELECT id FROM t;
")
echo "$ORD_ID"

# Asignar + iniciar
curl -sS -X POST "$API/agenda/ordenes/$MAN/asignar" \
  -H 'Content-Type: application/json' \
  -d "{\"fecha\":\"$(date -u +%F)\",\"turno\":\"am\",\"tecnicoId\":\"$TEC_ID\"}" >/dev/null

curl -sS -X POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$MAN/iniciar" >/dev/null

# Cerrar con un material (materialIdInt=3)
CLOSE_PAYLOAD='{
  "materiales":[{"materialIdInt":3,"cantidad":1}],
  "firmaBase64":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFygJp2k1gWQAAAABJRU5ErkJggg==",
  "evidenciasBase64":["data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFygJp2k1gWQAAAABJRU5ErkJggg=="]
}'

echo
echo "----- CERRAR $MAN -----"
HTTP_CODE=$(curl -sS -o /tmp/_close_body -w '%{http_code}' \
  -X POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$MAN/cerrar" \
  -H 'Content-Type: application/json' -d "$CLOSE_PAYLOAD")
echo
echo "HTTP cierre = $HTTP_CODE"
echo -n "BODY: "
sed -n '1,200p' /tmp/_close_body

if [[ "$HTTP_CODE" != "201" ]]; then
  echo "❌ Cierre MAN falló (HTTP $HTTP_CODE)"; exit 1
fi
echo "✅ Cierre MAN llegó con 201."

echo
echo "==================== 3) Validaciones en DB ===================="

echo
echo "→ orden_materiales de la orden:"
ROW=$(psqlc "SELECT id, material_id, material_id_int, cantidad, COALESCE(descontado,false)
             FROM orden_materiales
             WHERE orden_id='$ORD_ID'
             ORDER BY created_at DESC LIMIT 1;")
echo "$ROW"

MAT_UUID=$(echo "$ROW" | cut -d'|' -f2)
if [[ -z "$MAT_UUID" ]]; then
  echo "❌ orden_materiales.material_id vino NULL"; exit 1
fi
echo "✅ orden_materiales.material_id NO es NULL."

echo
echo "==================== 3B) Prueba de MERGE en orden_materiales (inserción directa controlada) ===================="

MAT_INT=$(echo "$ROW" | cut -d'|' -f3)
psqlc "INSERT INTO orden_materiales (orden_id, material_id, material_id_int, cantidad, descontado)
       VALUES ('$ORD_ID', NULL, $MAT_INT, 1, TRUE);"
psqlc "INSERT INTO orden_materiales (orden_id, material_id, material_id_int, cantidad, descontado)
       VALUES ('$ORD_ID', NULL, $MAT_INT, 1, TRUE);"

SUM_FILA=$(psqlc "SELECT COALESCE(SUM(cantidad),0), COUNT(*)
                  FROM orden_materiales
                  WHERE orden_id='$ORD_ID' AND material_id_int=$MAT_INT;")
SUM_CANT=$(echo "$SUM_FILA" | cut -d'|' -f1)
NFILAS=$(echo "$SUM_FILA" | cut -d'|' -f2)
echo "→ SUM(cantidad)=$SUM_CANT | filas=$NFILAS"

if [[ "$NFILAS" != "1" ]]; then
  echo "❌ MERGE falló en orden_materiales (hay $NFILAS filas)"; exit 1
fi
echo "✅ MERGE ok en orden_materiales (1 sola fila, cantidades acumuladas)."

echo
echo "==================== 3C) Verificación de inv_tecnico (no-duplicados + merge) ===================="

MAT_INT_DB=$(psqlc "SELECT material_id_int FROM orden_materiales WHERE orden_id='$ORD_ID' AND material_id_int=$MAT_INT LIMIT 1;")
if [[ -z "$MAT_INT_DB" ]]; then
  echo "❌ No pude obtener material_id_int desde orden_materiales."; exit 1
fi

DUPS=$(psqlc "SELECT COUNT(*) FROM (
                SELECT 1 FROM inv_tecnico WHERE tecnico_id='$TEC_ID' GROUP BY tecnico_id, material_id HAVING COUNT(*)>1
              ) s;")
if [[ "$DUPS" != "0" ]]; then
  echo "❌ Hay duplicados previos en inv_tecnico"; exit 1
fi
echo "✅ inv_tecnico sin duplicados por (tecnico_id, material_id)."

BEFORE=$(psqlc "SELECT COALESCE((SELECT cantidad::int FROM inv_tecnico WHERE tecnico_id='$TEC_ID' AND material_id=$MAT_INT_DB),0);")

psqlc "INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad) VALUES ('$TEC_ID', $MAT_INT_DB, 1);"
psqlc "INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad) VALUES ('$TEC_ID', $MAT_INT_DB, 1);"

AFTER=$(psqlc "SELECT COALESCE((SELECT cantidad::int FROM inv_tecnico WHERE tecnico_id='$TEC_ID' AND material_id=$MAT_INT_DB),0);")
echo "→ BEFORE=$BEFORE | AFTER=$AFTER"

if (( AFTER < BEFORE + 2 )); then
  echo "❌ Merge en inv_tecnico no acumuló correctamente (esperado >= $((BEFORE+2)))"; exit 1
fi

DUPS_PAIR=$(psqlc "SELECT COUNT(*) FROM inv_tecnico WHERE tecnico_id='$TEC_ID' AND material_id=$MAT_INT_DB;")
if [[ "$DUPS_PAIR" != "1" ]]; then
  echo "❌ Hay $DUPS_PAIR filas para (tecnico_id, material_id) en inv_tecnico"; exit 1
fi

echo "✅ Merge/Upsert en inv_tecnico correcto (1 fila, cantidad acumulada)."
echo
echo "🎉 Todo OK."
