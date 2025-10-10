#!/usr/bin/env bash
# script/smoke_materiales_ciclo.sh
set -euo pipefail

API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"
MAT_ID="${MAT_ID:-5}"                # 5 = DROP-FO en tu seed
CANT="${CANT:-5}"                    # cantidad a mover en el ciclo
ALM_CENTRAL_ID="74564bfe-a758-4057-9cbf-9ece34601702"
ALM_CENTRAL_COD="CENTRAL"
ALM_PRINC_ID="11111111-1111-1111-1111-111111111111"
ALM_PRINC_COD="ALM-PRINC"
TEC_ID="6"
ALM_TEC6_ID="62ebd37f-44c4-499d-b9ed-7bee75b09275"   # almacén del técnico 6
TEC_COD="TEC-6"

hdr_api() { echo -H "x-api-key: ${KEY}" -H "content-type: application/json"; }

get_qty_alm() {
  local cod="$1" mid="$2"
  curl -s ${API}/v1/inventario/stock/almacen/${cod} | jq -r --argjson mid "${mid}" '
    map(select(.material_id == $mid)) | (.[0].cantidad // "0") | tonumber
  '
}

get_qty_tec() {
  local tec="$1" mid="$2"
  curl -s ${API}/v1/inventario/tecnicos/${tec}/stock | jq -r --argjson mid "${mid}" '
    map(select(.material_id == $mid)) | (.[0].cantidad // "0") | tonumber
  '
}

idem_post_mov() {
  local payload="$1" key="$2"
  # intento y reintento idempotente
  curl -s -D- -X POST "${API}/v1/inventario/movimientos" \
    -H "x-api-key: ${KEY}" -H "content-type: application/json" -H "Idempotency-Key: ${key}" \
    -d "${payload}" \
  | sed -n '1,200p'
  curl -s -D- -X POST "${API}/v1/inventario/movimientos" \
    -H "x-api-key: ${KEY}" -H "content-type: application/json" -H "Idempotency-Key: ${key}" \
    -d "${payload}" \
  | sed -n '1,200p'
}

echo "== materiales: ciclo completo (materialId=${MAT_ID}) =="

CENT_BEFORE=$(get_qty_alm "${ALM_CENTRAL_COD}" "${MAT_ID}")
TEC_BEFORE=$(get_qty_tec "${TEC_ID}" "${MAT_ID}")
PRINC_BEFORE=$(get_qty_alm "${ALM_PRINC_COD}" "${MAT_ID}")
echo "Baseline: ${ALM_CENTRAL_COD}=${CENT_BEFORE} | ${TEC_COD}=${TEC_BEFORE} | ${ALM_PRINC_COD}=${PRINC_BEFORE}"

# 1) Asegurar stock en CENTRAL (si está por debajo de CANT, hacemos ingreso idempotente)
if (( $(printf "%.0f" "${CENT_BEFORE}") < ${CANT} )); then
  echo "-- CENTRAL bajo stock: ingreso inicial idempotente (+$CANT)"
  IDK="SMK-MAT-ING-$(date +%s)"
  idem_post_mov "$(jq -n \
    --argjson m "${MAT_ID}" --argjson q "${CANT}" \
    --arg to "${ALM_CENTRAL_ID}" --arg nota "smoke ingreso ${MAT_ID} a CENTRAL" '
    {tipo:"ingreso", materialId:$m, cantidad:$q, toAlmacenId:$to, nota:$nota}
  ')" "${IDK}" >/dev/null
fi

# 2) Traslado CENTRAL -> TEC-6
echo "-- Traslado ${CANT} ${MAT_ID} ${ALM_CENTRAL_COD} -> ${TEC_COD} (idempotente)"
IDK="SMK-MAT-TRL-$(date +%s)"
idem_post_mov "$(jq -n \
  --argjson m "${MAT_ID}" --argjson q "${CANT}" \
  --arg from "${ALM_CENTRAL_ID}" --arg to "${ALM_TEC6_ID}" \
  --argjson tec "${TEC_ID}" --arg nota "smoke CENTRAL -> TEC-6 ${MAT_ID}" '
  {tipo:"traslado", materialId:$m, cantidad:$q, fromAlmacenId:$from, toAlmacenId:$to, tecnicoId:$tec, nota:$nota}
')" "${IDK}" >/dev/null

CENT_AFTER_TRL=$(get_qty_alm "${ALM_CENTRAL_COD}" "${MAT_ID}")
TEC_AFTER_TRL=$(get_qty_tec "${TEC_ID}" "${MAT_ID}")
echo "Post-traslado: ${ALM_CENTRAL_COD}=${CENT_AFTER_TRL} | ${TEC_COD}=${TEC_AFTER_TRL}"

# 3) Devolución TEC-6 -> ALM-PRINC
echo "-- Devolución ${CANT} ${MAT_ID} ${TEC_COD} -> ${ALM_PRINC_COD} (idempotente)"
IDK="SMK-MAT-DEV-$(date +%s)"
idem_post_mov "$(jq -n \
  --argjson m "${MAT_ID}" --argjson q "${CANT}" \
  --arg from "${ALM_TEC6_ID}" --arg to "${ALM_PRINC_ID}" \
  --argjson tec "${TEC_ID}" --arg nota "smoke TEC-6 -> ALM-PRINC ${MAT_ID}" '
  {tipo:"traslado", materialId:$m, cantidad:$q, fromAlmacenId:$from, toAlmacenId:$to, tecnicoId:$tec, nota:$nota}
')" "${IDK}" >/dev/null

CENT_FINAL=$(get_qty_alm "${ALM_CENTRAL_COD}" "${MAT_ID}")
TEC_FINAL=$(get_qty_tec "${TEC_ID}" "${MAT_ID}")
PRINC_FINAL=$(get_qty_alm "${ALM_PRINC_COD}" "${MAT_ID}")
echo "Post-devolución: ${ALM_CENTRAL_COD}=${CENT_FINAL} | ${TEC_COD}=${TEC_FINAL} | ${ALM_PRINC_COD}=${PRINC_FINAL}"

echo "OK ciclo materiales."
