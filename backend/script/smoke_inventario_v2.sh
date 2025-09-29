#!/usr/bin/env bash
set -Eeuo pipefail

# --- Config ---------------------------------------------------------
API="${API:-http://127.0.0.1:3000}"
AUTH_HEADER="Authorization: Bearer ${TOKEN:-devtoken}"
CURL_BASE=(-sS --connect-timeout 5 --max-time 20 -H "$AUTH_HEADER" -H "Content-Type: application/json")
ID_PREFIX="invsmk-$(date +%Y%m%d-%H%M%S)"
TEC_ID="${TEC_ID:-c1f2dd81-8f1c-477c-b7cd-580dd13916d3}"

# --- Estilo ---------------------------------------------------------
c_reset=$'\e[0m'; c_dim=$'\e[2m'; c_bold=$'\e[1m'
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_info=$'\e[36m'

step() { echo; echo "${c_info}==> $*${c_reset}"; }
sub()  { echo "${c_dim}  -> $*${c_reset}"; }
ok()   { echo "${c_ok}✅ $*${c_reset}"; }
warn() { echo "${c_warn}⚠️  $*${c_reset}"; }
err()  { echo "${c_err}❌ $*${c_reset}"; }

# --- Helpers --------------------------------------------------------
curl_json() {
  local method=$1 path=$2 data=${3:-}
  local url="${API}${path}"
  sub "HTTP ${method} ${path}"
  if [[ -n "${data}" ]]; then
    echo "${c_dim}  payload:${c_reset} ${data}" | sed 's/^/    /'
  fi
  local tmp_body tmp_meta
  tmp_body=$(mktemp); tmp_meta=$(mktemp)
  if [[ -n "${data}" ]]; then
    curl "${CURL_BASE[@]}" -X "${method}" -d "${data}" -w '\n%{http_code} %{time_total}\n' "${url}" \
      | tee "${tmp_body}" \
      | tail -n1 > "${tmp_meta}"
  else
    curl "${CURL_BASE[@]}" -X "${method}" -w '\n%{http_code} %{time_total}\n' "${url}" \
      | tee "${tmp_body}" \
      | tail -n1 > "${tmp_meta}"
  fi
  local code time; read -r code time < "${tmp_meta}"
  sub "status=${code} time=${time}s"
  jq . "${tmp_body}" 2>/dev/null || cat "${tmp_body}"
  rm -f "${tmp_body}" "${tmp_meta}"
  [[ "${code}" =~ ^2 ]] || return 1
}

sql() {
  local q=$1
  sub "SQL:"
  echo "${c_dim}${q}${c_reset}" | sed 's/^/    /'
  docker compose exec -T db psql -U ispuser -d ispdb -v "ON_ERROR_STOP=1" -c "${q}"
}

# Cuenta filas con desviación != 0 en la vista (devuelve un número)
has_deviation() {
  docker compose exec -T db psql -U ispuser -d ispdb -At -c \
    "SELECT COALESCE(COUNT(*),0) FROM v_desviacion_inv_tecnico WHERE diff <> 0;" 2>/dev/null | tr -d '[:space:]'
}

# Snapshot espejo para un material en ambos almacenes
snapshot_espejo() {
  local mat_id=$1 alm_pri=$2 alm_tec=$3
  sql "
SELECT a.id AS almacen_id, a.tipo, a.tecnico_id,
       sa.material_id, sa.cantidad AS stock_almacen,
       it.cantidad AS inv_tecnico
FROM   almacenes a
LEFT JOIN stock_almacen sa
  ON sa.almacen_id=a.id AND sa.material_id=${mat_id}
LEFT JOIN inv_tecnico it
  ON it.tecnico_id=a.tecnico_id AND it.material_id=${mat_id}
WHERE a.id IN ('${alm_pri}','${alm_tec}')
ORDER BY a.tipo;"
}

mini_kardex() {
  local mat_id=$1 limit=${2:-10}
  sql "SELECT * FROM v_kardex WHERE material_id=${mat_id} ORDER BY created_at DESC LIMIT ${limit};"
}

# --- Prechequeos ----------------------------------------------------
step "Descubriendo IDs base (material y almacenes)"
MAT_ONT="$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT id FROM materiales ORDER BY id LIMIT 1;")"
ALM_PRI="$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT id FROM almacenes WHERE tipo='principal' LIMIT 1;")"
ALM_TEC="$(docker compose exec -T db psql -U ispuser -d ispdb -At -c "SELECT id FROM almacenes WHERE tipo='tecnico' LIMIT 1;")"
echo "MAT_ONT=${MAT_ONT}  ALM_PRI=${ALM_PRI}  ALM_TEC=${ALM_TEC}"

# Link almacén técnico <-> tecnico_id (requisito para espejo inv_tecnico)
step "Linkeando almacén técnico con TEC_ID (solo si no lo está)"
docker compose exec -T db psql -U ispuser -d ispdb -v "ON_ERROR_STOP=1" -c \
"UPDATE almacenes SET tecnico_id='${TEC_ID}' WHERE id='${ALM_TEC}' AND (tecnico_id IS NULL OR tecnico_id<> '${TEC_ID}');" >/dev/null || true
sql "SELECT id,tipo,tecnico_id FROM almacenes WHERE id='${ALM_TEC}';"

# --- Estado inicial -------------------------------------------------
step "Snapshot inicial (espejo stock_almacen vs inv_tecnico)"
snapshot_espejo "${MAT_ONT}" "${ALM_PRI}" "${ALM_TEC}"
mini_kardex "${MAT_ONT}" 5

# --- Escenario: ingreso -> transferencia -> devolución -> egreso ----
step "Ingreso 50 al almacén principal"
curl_json POST "/v1/inventario/movimientos" \
"{\"idempotencyKey\":\"${ID_PREFIX}-ing\",\"tipo\":\"ingreso\",\"almacenDestinoId\":\"${ALM_PRI}\",\"materialIdInt\":${MAT_ONT},\"cantidad\":50}" \
  || { err "falló ingreso"; exit 1; }
snapshot_espejo "${MAT_ONT}" "${ALM_PRI}" "${ALM_TEC}"

step "Transferencia 10 principal -> técnico"
curl_json POST "/v1/inventario/movimientos" \
"{\"idempotencyKey\":\"${ID_PREFIX}-p2t\",\"tipo\":\"transferencia\",\"almacenOrigenId\":\"${ALM_PRI}\",\"almacenDestinoId\":\"${ALM_TEC}\",\"materialIdInt\":${MAT_ONT},\"cantidad\":10}" \
  || { err "falló transferencia p->t"; exit 1; }
snapshot_espejo "${MAT_ONT}" "${ALM_PRI}" "${ALM_TEC}"

step "Devolución 2 técnico -> principal"
curl_json POST "/v1/inventario/movimientos" \
"{\"idempotencyKey\":\"${ID_PREFIX}-t2p\",\"tipo\":\"transferencia\",\"almacenOrigenId\":\"${ALM_TEC}\",\"almacenDestinoId\":\"${ALM_PRI}\",\"materialIdInt\":${MAT_ONT},\"cantidad\":2}" \
  || { err "falló devolución t->p"; exit 1; }
snapshot_espejo "${MAT_ONT}" "${ALM_PRI}" "${ALM_TEC}"

step "Egreso 1 del técnico (simula uso en cierre)"
curl_json POST "/v1/inventario/movimientos" \
"{\"idempotencyKey\":\"${ID_PREFIX}-eg\",\"tipo\":\"egreso\",\"almacenOrigenId\":\"${ALM_TEC}\",\"materialIdInt\":${MAT_ONT},\"cantidad\":1,\"refExterna\":\"INS-SMOKE\"}" \
  || { err "falló egreso técnico"; exit 1; }
snapshot_espejo "${MAT_ONT}" "${ALM_PRI}" "${ALM_TEC}"

# --- Consultas agregadas -------------------------------------------
step "Stock corporativo (principal / técnico)"
curl_json GET "/v1/inventario/stock?scope=principal" || true
curl_json GET "/v1/inventario/stock?scope=tecnico"   || true

step "Kardex último material (TOP 10)"
curl_json GET "/v1/inventario/kardex?materialIdInt=${MAT_ONT}" || true

# --- Extra: Sanidad de espejo e intento de autocorrección (solo DEV/CI)
step "Sanity espejo inv_tecnico (diff debe ser 0)"
sql "SELECT * FROM v_desviacion_inv_tecnico WHERE diff <> 0 ORDER BY tecnico_id, material_id;" || true

DEV_COUNT="$(has_deviation || echo 0)"
if [[ "${DEV_COUNT}" != "0" ]]; then
  warn "Hay ${DEV_COUNT} desviación(es). Reforzando espejo (idempotente, solo DEV/CI)…"
  sql "
UPDATE inv_tecnico it
SET cantidad = sa.cantidad
FROM almacenes a
JOIN stock_almacen sa ON sa.almacen_id = a.id
WHERE a.tipo='tecnico'
  AND a.tecnico_id = it.tecnico_id
  AND sa.material_id = it.material_id;" || true

  step "Sanity espejo inv_tecnico (post-fix)"
  sql "SELECT * FROM v_desviacion_inv_tecnico WHERE diff <> 0 ORDER BY tecnico_id, material_id;" || true
else
  ok "Espejo inv_tecnico en cero (OK)"
fi

ok "Smoke Inventario v2 (verboso) OK"
