#!/usr/bin/env bash
set -euo pipefail

API_V1="http://localhost:3000/v1"
TECNICO_ID=1
ALM_TEC='beb7a8f6-28a2-4ad2-b121-5619580ba82d'   # ajusta si tu técnico 1 tiene otro almacén
MATERIAL_ID=1

export PGPASSWORD="$(docker compose exec -T db printenv POSTGRES_PASSWORD)"
PSQL='psql -h 127.0.0.1 -p 5433 -U ispuser -d ispdb -v ON_ERROR_STOP=1 -t -A'

echo "== Smoke 0: estructura base =="
$PSQL -c "SELECT 'kardex_cols_ok'
           WHERE EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='kardex' AND column_name IN ('almacen_id','etiqueta','delta') GROUP BY 1 HAVING count(*)=3);"
$PSQL -c "SELECT 'kardex_rule_ok' FROM pg_rules WHERE schemaname='public' AND tablename='kardex' AND rulename='kardex_insert' LIMIT 1;"
$PSQL -c "SELECT 'trigger_ok' FROM pg_trigger
           WHERE tgrelid='public.movimientos'::regclass AND tgname='trg_movs_sync_stock' AND NOT tgisinternal;"

echo "== Smoke 1: iniciar/cerrar orden =="
NUEVO="MAN-$(date -u +%y%m%d%H%M%S)"
curl -s -X POST "$API_V1/tecnicos/$TECNICO_ID/ordenes/codigo/$NUEVO/iniciar" \
  -H 'Content-Type: application/json' -d '{}' | jq -r '._idempotent' | xargs -I{} echo "iniciar_idem={}"
curl -s -X POST "$API_V1/tecnicos/$TECNICO_ID/ordenes/codigo/$NUEVO/cerrar" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --argjson mid $MATERIAL_ID '{ materiales:[{materialId:$mid, cantidad:1}] }')" \
  | jq -r '"cerrar_estado="+.estado+" codigo="+.codigo'

echo "== Smoke 2: saldo vs stock tras cierre =="
Q="WITH s AS (SELECT SUM(delta) saldo FROM public.kardex WHERE almacen_id='${ALM_TEC}'::uuid AND material_id=${MATERIAL_ID})
   SELECT s.saldo||' '||its.stock FROM s JOIN public.inventario_tecnico_stock its ON its.tecnico_id=${TECNICO_ID} AND its.material_id=${MATERIAL_ID};"
read SALDO STOCK <<< $($PSQL -c "$Q")
echo "saldo=$SALDO stock=$STOCK"
[[ "$SALDO" = "$STOCK" ]] && echo "saldo==stock ✅" || (echo "saldo!=stock ❌"; exit 1)

echo "== Smoke 3: movimiento API (idempotente) y trigger =="
IDEMP=$(date -u +%s%N)
BEF=$SALDO
curl -s -X POST "$API_V1/inventario/movimientos" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg idk "$IDEMP" --arg alm "$ALM_TEC" \
        --argjson mid $MATERIAL_ID \
        '{ idempotencyKey:$idk, tipo:"egreso", almacenOrigenId:$alm, materialId:$mid, cantidad:1, motivo:"smoke"}')" \
  | jq -r '.id' | xargs -I{} echo "mov_id={}"

read SALDO2 STOCK2 <<< $($PSQL -c "$Q")
echo "post-mov saldo=$SALDO2 stock=$STOCK2"
[[ $((BEF-1)) -eq "$SALDO2" && "$SALDO2" = "$STOCK2" ]] && echo "trigger/stock ✅" || (echo "trigger/stock ❌"; exit 1)

echo "== Smoke 4: índices en movimientos =="
$PSQL -c "SELECT 'ix_dest_ok' FROM pg_indexes WHERE schemaname='public' AND tablename='movimientos' AND indexname='ix_movs_dest_mat_created';"
$PSQL -c "SELECT 'ix_orig_ok' FROM pg_indexes WHERE schemaname='public' AND tablename='movimientos' AND indexname='ix_movs_orig_mat_created';"

echo "✅ TODOS LOS SMOKES OK"
