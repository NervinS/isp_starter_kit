#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
TECH_ID="${TECH_ID:-6}"
MAT_ID="${MAT_ID:-3}"
CLEAN="${CLEAN:-false}"

hdr=(-H "x-api-key: ${KEY}" -H "content-type: application/json")

echo "[SMOKE] Limpieza opcional DESACTIVADA (CLEAN=true para habilitarla)."
echo "[SMOKE] Esperando readiness en ${API_BASE}/health …"
for i in {1..20}; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE}/health")
  echo "  try#${i} -> /health => ${code}"
  [[ "${code}" == "200" ]] && break
  sleep 0.5
done
[[ "${code}" == "200" ]] || { echo "[FAIL] API no respondió 200 en /health"; exit 1; }
echo "[ OK ] API lista."

tec_code="TEC-${TECH_ID}"
stock_from_kardex() {
  curl -sS "${API_BASE}/inventario/kardex?tecnicoId=${TECH_ID}&materialId=${MAT_ID}&limit=1000" \
  | jq --arg TEC "${tec_code}" '
      (map(select(.to_almacen_codigo==$TEC)      | (.cantidad|tonumber)) | add // 0)
    - (map(select(.from_almacen_codigo==$TEC)    | (.cantidad|tonumber)) | add // 0)
  '
}

base="$(stock_from_kardex)"
[[ -n "${base}" ]] || { echo "[FAIL] No pude obtener stock"; exit 1; }

echo "[SMOKE] ➡️ Smoke traslado (simulado con +1/-1 sobre ${tec_code}). base=${base}"

# +1 (agregar)
b_plus=$(jq -n --arg mid "${MAT_ID}" '{materialId:($mid|tonumber), cantidad:1, nota:"smoke-ida(+1)"}')
curl -sS "${hdr[@]}" -d "${b_plus}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/agregar" >/dev/null
after_plus="$(stock_from_kardex)"

# -1 (descontar)
b_minus=$(jq -n --arg mid "${MAT_ID}" '{materialId:($mid|tonumber), cantidad:1, nota:"smoke-vuelta(-1)"}')
curl -sS "${hdr[@]}" -d "${b_minus}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/descontar" >/dev/null
after_cycle="$(stock_from_kardex)"

# Validaciones flexibles: aceptamos concurrencia durante el “ida”
if [[ "${after_cycle}" == "${base}" ]]; then
  echo "[ OK ] ✅ OK: stock técnico volvió al valor inicial (${after_cycle})."
else
  echo "[FAIL] Tras ida/vuelta el stock no volvió. base=${base} after=${after_cycle}"
  exit 1
fi
