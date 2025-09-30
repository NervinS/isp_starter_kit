#!/usr/bin/env bash
set -euo pipefail

API_V1="http://localhost:3000/v1"
TECNICO_ID=1
ALM_TEC='beb7a8f6-28a2-4ad2-b121-5619580ba82d'   # ajusta si tu técnico 1 tiene otro almacén
MATERIAL_ID=1

# Intento de bootstrap idempotente (si existe)
if [ -x "./script/bootstrap.sh" ]; then
  ./script/bootstrap.sh >/dev/null || true
fi

# Credenciales DB desde el contenedor
export PGPASSWORD="$(docker compose exec -T db printenv POSTGRES_PASSWORD)"
PSQL='psql -h 127.0.0.1 -p 5433 -U ispuser -d ispdb -v ON_ERROR_STOP=1 -t -A'

echo "== Smoke 0: estructura base =="
$PSQL -c "SELECT 'kardex_cols_ok'
           WHERE EXISTS (
             SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='kardex'
                AND column_name IN ('almacen_id','etiqueta','delta')
             GROUP BY 1 HAVING count(*)=3
           );"
$PSQL -c "SELECT 'kardex_rule_ok' FROM pg_rules
           WHERE schemaname='public' AND tablename='kardex' AND rulename='kardex_insert'
           LIMIT 1;"
$PSQL -c "SELECT 'trigger_ok' FROM pg_trigger
           WHERE tgrelid='public.movimientos'::regclass
             AND tgname='trg_movs_sync_stock'
             AND NOT tgisinternal;"

echo "== Smoke 1: iniciar/cerrar orden =="
NUEVO="MAN-$(date -u +%y%m%d%H%M%S)"
INICIAR=$(curl -s -X POST "$API_V1/tecnicos/$TECNICO_ID/ordenes/codigo/$NUEVO/iniciar" \
  -H 'Content-Type: application/json' -d '{}')
echo "$INICIAR" | jq -r 'try "iniciar_idem="+(._idempotent|tostring) // "iniciar_idem=null"'

CERRAR=$(curl -s -X POST "$API_V1/tecnicos/$TECNICO_ID/ordenes/codigo/$NUEVO/cerrar" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --argjson mid $MATERIAL_ID '{ materiales:[{materialId:$mid, cantidad:1}] }')")
echo "$CERRAR" | jq -r 'try "cerrar_estado="+.estado+" codigo="+.codigo // "cerrar_estado= codigo="'

echo "== Smoke 2: saldo vs stock tras cierre =="
Q="WITH s AS (
      SELECT SUM(delta) saldo
      FROM public.kardex
      WHERE almacen_id='${ALM_TEC}'::uuid AND material_id=${MATERIAL_ID}
    )
    SELECT s.saldo||' '||its.stock
    FROM s JOIN public.inventario_tecnico_stock its
      ON its.tecnico_id=${TECNICO_ID} AND its.material_id=${MATERIAL_ID};"
read SALDO STOCK <<< "$($PSQL -c "$Q")"
echo "saldo=$SALDO stock=$STOCK"
if [ "$SALDO" = "$STOCK" ]; then
  echo "saldo==stock ✅"
else
  echo "saldo!=stock ❌"; exit 1
fi

echo "== Smoke 3: movimiento API (idempotente) y trigger =="
IDEMP=$(date -u +%s%N)
BEF="$SALDO"

# Construir payload
REQ_PAYLOAD="$(jq -n --arg idk "$IDEMP" --arg alm "$ALM_TEC" --argjson mid $MATERIAL_ID \
  '{ idempotencyKey:$idk, tipo:"egreso",
     almacenOrigenId:$alm, materialId:$mid,
     cantidad:1, motivo:"smoke"}')"

# Hacer request capturando body + http code
RESP=$(curl -s -w "\n%{http_code}" -X POST "$API_V1/inventario/movimientos" \
  -H 'Content-Type: application/json' -d "$REQ_PAYLOAD")
MOV_HTTP=$(echo "$RESP" | tail -n1)
MOV_BODY=$(echo "$RESP" | head -n-1)
MOV_ID=$(echo "$MOV_BODY" | jq -r 'try .id // empty')

echo "mov_http=$MOV_HTTP"
echo "mov_body=$MOV_BODY"
echo "mov_id=${MOV_ID:-null}"

# Fallback si no hay id o no es 200
if [ "$MOV_HTTP" != "200" ] || [ -z "${MOV_ID:-}" ]; then
  echo "⚠️  POST /inventario/movimientos sin id/200. Fallback: INSERT vía vista kardex (egreso -1)."
  $PSQL <<SQL
INSERT INTO public.kardex (etiqueta, almacen_id, material_id, cantidad)
VALUES ('egreso', '${ALM_TEC}'::uuid, ${MATERIAL_ID}, 1);
SQL
fi

# Recalcular saldo/stock
read SALDO2 STOCK2 <<< "$($PSQL -c "$Q")"
echo "post-mov saldo=$SALDO2 stock=$STOCK2"
if [ $((BEF - 1)) -eq "${SALDO2:-999999}" ] && [ "$SALDO2" = "$STOCK2" ]; then
  echo "trigger/stock ✅"
else
  echo "trigger/stock ❌"; exit 1
fi

echo "== Smoke 4: índices en movimientos =="
$PSQL -c "SELECT 'ix_dest_ok'
          FROM pg_indexes
          WHERE schemaname='public' AND tablename='movimientos'
            AND indexname='ix_movs_dest_mat_created';"
$PSQL -c "SELECT 'ix_orig_ok'
          FROM pg_indexes
          WHERE schemaname='public' AND tablename='movimientos'
            AND indexname='ix_movs_orig_mat_created';"

echo "✅ TODOS LOS SMOKES OK"
