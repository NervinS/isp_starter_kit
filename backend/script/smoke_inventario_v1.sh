# --- Mini-smoke: espejo inv_tecnico ---
TEC_ID="c1f2dd81-8f1c-477c-b7cd-580dd13916d3"
MAT_ONT=${MAT_ONT:-$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT id FROM materiales ORDER BY id LIMIT 1;")}
ALM_TEC=${ALM_TEC:-$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT id FROM almacenes WHERE tipo='tecnico' LIMIT 1;")}

CNT_LINK=$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT COUNT(*) FROM almacenes WHERE id='${ALM_TEC}' AND tecnico_id='${TEC_ID}';")
test "$CNT_LINK" = "1" || { echo "❌ almacén técnico no linkeado a TEC_ID"; exit 1; }

docker compose exec -T db psql -U ispuser -d ispdb -c "UPDATE stock_almacen SET cantidad=cantidad WHERE almacen_id='${ALM_TEC}' AND material_id=${MAT_ONT};" >/dev/null

read -r SA IT <<<"$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "
  SELECT COALESCE(sa.cantidad,0), COALESCE(it.cantidad,0)
  FROM (SELECT cantidad FROM stock_almacen WHERE almacen_id='${ALM_TEC}' AND material_id=${MAT_ONT}) sa
  FULL JOIN (SELECT cantidad FROM inv_tecnico WHERE tecnico_id='${TEC_ID}' AND material_id=${MAT_ONT}) it ON TRUE;
")"
if [ "$SA" = "$IT" ]; then
  echo "✅ Espejo inv_tecnico OK (stock=${SA})"
else
  echo "❌ Mismatch inv_tecnico (stock_almacen=${SA} inv_tecnico=${IT})"; exit 1
fi
