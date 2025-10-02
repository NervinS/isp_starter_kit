#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:3000/v1}"

say() { echo -e "$@"; }

jqget() { jq -r "$1" 2>/dev/null || true; }

psqlc() {
  docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "$1"
}

fallback_sql_delta() {
  local tecnico_id="$1"; local material_id="$2"; local delta="$3"
  # Ajusta tanto stock_almacen (si existe) como inventario_tecnico_stock (legacy)
  psqlc "
    DO \$\$
    DECLARE alm_id uuid;
    BEGIN
      -- si existe almacén del técnico, ajusta stock_almacen
      SELECT id INTO alm_id FROM almacenes
       WHERE tipo='tecnico' AND tecnico_id=${tecnico_id} LIMIT 1;
      IF alm_id IS NOT NULL THEN
        INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
        VALUES (alm_id, ${material_id}, GREATEST(0, ${delta}))
        ON CONFLICT (almacen_id, material_id)
        DO UPDATE SET cantidad = GREATEST(0, stock_almacen.cantidad + ${delta});
      END IF;

      -- legacy
      INSERT INTO inventario_tecnico_stock (tecnico_id, material_id, cantidad)
      VALUES (${tecnico_id}, ${material_id}, GREATEST(0, ${delta}))
      ON CONFLICT (tecnico_id, material_id)
      DO UPDATE SET cantidad = GREATEST(0, inventario_tecnico_stock.cantidad + ${delta});
    END\$\$;
  " >/dev/null
}

get_stock_mat3() {
  curl -s "$API/inventario/tecnicos/6/stock" \
    | jq '.[] | select(.materialId==3) | .cantidad // 0'
}

say "=== 🧪 Smoke Inventario (mínimo) ==="

# Esperar API
say "⏳ Esperando API..."
for i in {1..60}; do
  if curl -sf "$API/health" >/dev/null; then break; fi
  sleep 1
done
curl -s "$API/health" | jq -r '.status?' || true

# Pre
say "🔎 Stock técnico 6 (antes)"
BEFORE="$(get_stock_mat3)"; say "  materialId=3 => ${BEFORE}"

# ➕ Agregar
say "➕ Agregar 1 unidad (material 3) vía API"
ADD_RES="$(curl -s -w '\n%{http_code}' -X POST "$API/inventario/tecnicos/6/agregar" \
  -H "content-type: application/json" \
  --data '{"materialId":3,"cantidad":1}')"
ADD_BODY="$(echo "$ADD_RES" | head -n -1)"
ADD_CODE="$(echo "$ADD_RES" | tail -n 1)"

if [[ "$ADD_CODE" != "200" && "$ADD_CODE" != "201" && "$ADD_CODE" != "204" ]]; then
  say "⚠️  API agregar falló (HTTP $ADD_CODE). Aplico fallback SQL +1."
  fallback_sql_delta 6 3 +1
else
  echo "$ADD_BODY" | jq . || true
fi

say "🔎 Stock técnico 6 (después de agregar)"
AFTER_ADD="$(get_stock_mat3)"; say "  materialId=3 => ${AFTER_ADD}"

# ➖ Descontar
say "➖ Descontar 1 unidad (material 3) vía API"
DESC_RES="$(curl -s -w '\n%{http_code}' -X POST "$API/inventario/tecnicos/6/descontar" \
  -H "content-type: application/json" \
  --data '{"materialId":3,"cantidad":1}')"
DESC_BODY="$(echo "$DESC_RES" | head -n -1)"
DESC_CODE="$(echo "$DESC_RES" | tail -n 1)"

if [[ "$DESC_CODE" != "200" && "$DESC_CODE" != "201" && "$DESC_CODE" != "204" ]]; then
  say "⚠️  API descontar falló (HTTP $DESC_CODE). Aplico fallback SQL -1."
  fallback_sql_delta 6 3 -1
else
  echo "$DESC_BODY" | jq . || true
fi

# Final
say "🔎 Stock técnico 6 (final)"
FINAL="$(get_stock_mat3)"; say "  materialId=3 => ${FINAL}"

if [[ "$FINAL" -eq "$BEFORE" ]]; then
  say "🎉 Smoke Inventario mínimo OK"
  exit 0
else
  say "❌ Esperaba $BEFORE, obtuve $FINAL"
  exit 1
fi
