#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="$API_BASE/v1"
KEY="${KEY:-superdev}"
TEC_ID="${TEC_ID:-6}"
FROM_ALM="${FROM_ALM:-CENTRAL}"
TO_ALM="TEC-$TEC_ID"

# Usar un material que nadie más toca en los otros smokes: 4 = "MAT-CABLE"
MAT_ID="${MAT_ID:-4}"
CANT="${CANT:-1}"

logdir="$(dirname "$0")/../logs"
mkdir -p "$logdir"

echo "[SMOKE] Limpieza opcional DESACTIVADA (CLEAN=true para habilitarla)."

# Espera de readiness
echo "[SMOKE] Esperando readiness en $API_BASE/health …"
for i in {1..5}; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE/health" || true)"
  echo "  try#$i -> /health => $code"
  if [[ "$code" == "200" ]]; then
    echo "[ OK ] API lista."
    break
  fi
  sleep 1
done

# Baseline del técnico para el material aislado
base_json="$(curl -s -H "x-api-key: $KEY" "$API/inventario/tecnicos/$TEC_ID/stock")"
base_qty="$(echo "$base_json" | jq -r ".[] | select(.material_id==$MAT_ID) | .cantidad" || true)"
base_qty="${base_qty:-0}"
base_qty="${base_qty%.*}" # normaliza "N.00" a "N"

echo "[SMOKE] ➡️ Smoke traslado (aislado materialId=$MAT_ID, $FROM_ALM <-> $TO_ALM). base=$base_qty"

run_id="$(date +%s)-$RANDOM"
nota_up="smoke traslado aislado +$CANT #$run_id"
nota_down="smoke devolucion aislada -$CANT #$run_id"

# 1) Traslado FROM -> TEC (idempotente)
resp_up="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/movimientos" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT_ID,\"cantidad\":$CANT,\"fromAlmacen\":\"$FROM_ALM\",\"toAlmacen\":\"$TO_ALM\",\"tecnicoId\":$TEC_ID,\"nota\":\"$nota_up\"}")"
echo "$resp_up" | jq . >/dev/null || { echo "[FAIL] Respuesta inválida en traslado up"; exit 1; }

# repetir para idempotencia
resp_up2="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/movimientos" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT_ID,\"cantidad\":$CANT,\"fromAlmacen\":\"$FROM_ALM\",\"toAlmacen\":\"$TO_ALM\",\"tecnicoId\":$TEC_ID,\"nota\":\"$nota_up\"}")" >/dev/null

# 2) Traslado TEC -> ALM-PRINC (idempotente)
resp_down="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/movimientos" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT_ID,\"cantidad\":$CANT,\"fromAlmacen\":\"$TO_ALM\",\"toAlmacen\":\"ALM-PRINC\",\"tecnicoId\":$TEC_ID,\"nota\":\"$nota_down\"}")"
echo "$resp_down" | jq . >/dev/null || { echo "[FAIL] Respuesta inválida en traslado down"; exit 1; }

# repetir para idempotencia
resp_down2="$(curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/movimientos" \
  -d "{\"tipo\":\"traslado\",\"materialId\":$MAT_ID,\"cantidad\":$CANT,\"fromAlmacen\":\"$TO_ALM\",\"toAlmacen\":\"ALM-PRINC\",\"tecnicoId\":$TEC_ID,\"nota\":\"$nota_down\"}")" >/dev/null

# 3) Comprobar que el stock volvió a baseline
after_json="$(curl -s -H "x-api-key: $KEY" "$API/inventario/tecnicos/$TEC_ID/stock")"
after_qty="$(echo "$after_json" | jq -r ".[] | select(.material_id==$MAT_ID) | .cantidad" || true)"
after_qty="${after_qty:-0}"
after_qty="${after_qty%.*}"

if [[ "$after_qty" == "$base_qty" ]]; then
  echo "[ OK ] ✅ OK: stock técnico volvió al valor inicial ($after_qty)."
  exit 0
else
  echo "[FAIL] Tras ida/vuelta el stock no volvió. base=$base_qty after=$after_qty (materialId=$MAT_ID)"
  exit 1
fi
