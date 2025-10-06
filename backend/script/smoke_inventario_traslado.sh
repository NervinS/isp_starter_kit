#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
DB_USER="${DB_USER:-ispuser}"
DB_NAME="${DB_NAME:-ispdb}"

MAT_ID="${MAT_ID:-3}"
TECNICO_ID="${TECNICO_ID:-6}"

say() { echo -e "$@"; }

# Helper: psql dentro del contenedor
psqlc() {
  docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -At -c "$1"
}

# Helper: stock del técnico por API
get_stock_tecnico_mat() {
  curl -s -H "x-api-key: ${KEY}" "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" \
    | jq -r --arg mid "${MAT_ID}" '.[] | select((.material_id==($mid|tonumber)) or (.materialId==($mid|tonumber))) | .cantidad // 0' \
    || echo "0"
}

say "➡️ Smoke traslado dinámico (elige origen con saldo, ida y vuelta)"

# 1) Resolver IDs
CENTRAL_ID="$(psqlc "SELECT id FROM public.almacenes WHERE codigo='CENTRAL' LIMIT 1;")"
PRINCIPAL_ID="$(psqlc "SELECT id FROM public.almacenes WHERE codigo='PRINCIPAL' LIMIT 1;")"
TEC6_ID="$(psqlc "SELECT id FROM public.almacenes WHERE tipo='tecnico' AND tecnico_id=${TECNICO_ID} LIMIT 1;")"

# 2) Elegir origen con saldo (prioriza CENTRAL)
ORIGEN_ID=""
for cand in "${CENTRAL_ID}" "${PRINCIPAL_ID}"; do
  [[ -z "$cand" ]] && continue
  has_stock="$(psqlc "SELECT COALESCE((SELECT cantidad FROM public.stock_almacen WHERE almacen_id='${cand}' AND material_id=${MAT_ID}),0);")"
  if [[ "${has_stock}" -ge 1 ]]; then ORIGEN_ID="${cand}"; break; fi
done

if [[ -z "${ORIGEN_ID}" ]]; then
  say "ℹ️ No hay saldo ni en CENTRAL ni en PRINCIPAL para mat=${MAT_ID}. Pre-cargando +1 en CENTRAL (ajuste)…"
  psqlc "INSERT INTO public.movimientos (tipo, material_id, cantidad, to_almacen_id, fecha, nota)
         VALUES ('ajuste', ${MAT_ID}, 1, '${CENTRAL_ID}', now(), 'preload smoke traslado');" >/dev/null
  ORIGEN_ID="${CENTRAL_ID}"
fi

say "IDs: ORIGEN=${ORIGEN_ID}  DESTINO(tec6)=${TEC6_ID}"

# 3) Medir stock técnico antes
s0="$(get_stock_tecnico_mat)"
say "🔎 Stock TEC-${TECNICO_ID} (antes) => ${s0}"

# 4) Traslado ida (origen -> TEC-6)
say "➡️ Ida: ${ORIGEN_ID} -> ${TEC6_ID}"
psqlc "SELECT public.fn_mov_traslado('${ORIGEN_ID}', '${TEC6_ID}', ${MAT_ID}, 1, 'smoke traslado ida');" >/dev/null

s1="$(get_stock_tecnico_mat)"
say "🔎 Stock TEC-${TECNICO_ID} (después ida) => ${s1}"

# 5) Traslado vuelta (TEC-6 -> origen)
say "⬅️ Vuelta: ${TEC6_ID} -> ${ORIGEN_ID}"
psqlc "SELECT public.fn_mov_traslado('${TEC6_ID}', '${ORIGEN_ID}', ${MAT_ID}, 1, 'smoke traslado vuelta');" >/dev/null

s2="$(get_stock_tecnico_mat)"
say "🔎 Stock TEC-${TECNICO_ID} (después vuelta) => ${s2}"

if [[ "${s0}" -eq "${s2}" ]]; then
  say "🎉 OK: stock técnico volvió al valor inicial (${s0})."
else
  say "❌ Stock técnico no volvió al valor inicial (antes=${s0}, final=${s2})."
  exit 1
fi
