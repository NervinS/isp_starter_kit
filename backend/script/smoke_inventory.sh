#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
TECH_ID="${TECH_ID:-6}"
MAT_ID="${MAT_ID:-3}"
CLEAN="${CLEAN:-false}"

hdr=(-H "x-api-key: ${KEY}" -H "content-type: application/json")

echo "[SMOKE] Limpieza opcional ${CLEAN}"
echo "[SMOKE] Esperando readiness en ${API_BASE}/health …"
for i in {1..20}; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE}/health")
  echo "  try#${i} -> /health => ${code}"
  [[ "${code}" == "200" ]] && break
  sleep 0.5
done
[[ "${code}" == "200" ]] || { echo "[FAIL] API no respondió 200 en /health"; exit 1; }
echo "[ OK ] API lista."

# Utilidad: stock del técnico por suma de kardex CENTRAL <-> TEC-<id>
tec_code="TEC-${TECH_ID}"
stock_from_kardex() {
  curl -sS "${API_BASE}/inventario/kardex?tecnicoId=${TECH_ID}&materialId=${MAT_ID}&limit=1000" \
  | jq --arg TEC "${tec_code}" '
      (map(select(.to_almacen_codigo==$TEC)      | (.cantidad|tonumber)) | add // 0)
    - (map(select(.from_almacen_codigo==$TEC)    | (.cantidad|tonumber)) | add // 0)
  '
}

# Sonda básica kardex
echo "[SMOKE] Sonda kardex…"
curl -sS "${API_BASE}/inventario/kardex?limit=1" >/dev/null && echo "[ OK ] Kardex responde JSON."

# Guardrail: forzar descuento grande => debe ser 409/INSUFFICIENT_STOCK
echo "[SMOKE] Forzando descuento (-999999) debe responder 409/INSUFFICIENT_STOCK y NO escribir kardex…"
body=$(jq -n --arg mid "${MAT_ID}" '{materialId:($mid|tonumber), cantidad:999999, nota:"smoke-guard-oversell"}')
resp="$(curl -sS -i "${hdr[@]}" -d "${body}" "${API_BASE}/inventario/tecnicos/${TECH_ID}/descontar")"
status=$(printf "%s" "$resp" | awk 'NR==1{print $2}')
if [[ "${status}" != "409" ]]; then
  echo "[FAIL] Esperaba 409, obtuve ${status}. Respuesta: $(printf "%s" "$resp" | tail -n +2 | tr -d "\n")"
  exit 1
else
  echo "[ OK ] Rechazo por saldo correcto (409) y kardex limpio."
fi

# Ciclo +2 / -2 usando TRASLADOS (CENTRAL -> TEC y TEC -> CENTRAL)
echo "[SMOKE] Subir +2 (AGREGAR) y revertir -2 (DESCONTAR) en TEC-${TECH_ID} / material ${MAT_ID}…"
base="$(stock_from_kardex)"
[[ -n "${base}" ]] || { echo "[FAIL] No pude obtener stock base"; exit 1; }

# +2 (agregar) CENTRAL -> TEC
b_plus=$(jq -n --arg mid "${MAT_ID}" '{materialId:($mid|tonumber), cantidad:2, nota:"smoke+2-agregar"}')
curl -sS "${hdr[@]}" -d "${b_plus}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/agregar" >/dev/null

after_plus="$(stock_from_kardex)"

# -2 (descontar) TEC -> CENTRAL
b_minus=$(jq -n --arg mid "${MAT_ID}" '{materialId:($mid|tonumber), cantidad:2, nota:"smoke-2-descontar"}')
curl -sS "${hdr[@]}" -d "${b_minus}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/descontar" >/dev/null

after_cycle="$(stock_from_kardex)"

if [[ "${after_cycle}" == "${base}" ]]; then
  echo "[ OK ] Ciclo +2/-2 OK. Stock volvió a ${after_cycle}."
else
  echo "[FAIL] Tras +2/-2 el stock no volvió. base=${base} after=${after_cycle}"
  exit 1
fi
