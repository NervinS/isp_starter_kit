#!/usr/bin/env bash
# script/smoke_inventory.sh
# Smoke de inventario (OSS/BSS) con verificación de consistencia y autorepair seguro.
set -euo pipefail

# ---------- Config ----------
API_BASE="${API_BASE:-http://localhost:3000/v1}"
API_KEY_HEADER="${API_KEY_HEADER:-x-api-key: superdev}"
TECH_ID="${TECH_ID:-6}"
MAT_ID="${MAT_ID:-3}"
READINESS_TRIES="${READINESS_TRIES:-60}"
KARDEX_LIMIT="${KARDEX_LIMIT:-10}"
DC="${DC:-docker compose}"

# Limpieza y autorreparación
CLEAN="${CLEAN:-false}"
AUTO_REPAIR_STOCK="${AUTO_REPAIR_STOCK:-false}"         # activa pipeline de reparación
AUTO_REPAIR_PREVIEW="${AUTO_REPAIR_PREVIEW:-true}"      # dry-run previo
AUTO_REPAIR_CONFIRM="${AUTO_REPAIR_CONFIRM:-false}"     # segunda confirmación requerida

# Timeouts psql
DEBUG="${DEBUG:-false}"
PSQL_TIMEOUT="${PSQL_TIMEOUT:-8s}"                # timeout externo (coreutils timeout); 0s=deshabilita
PSQL_STMT_TIMEOUT="${PSQL_STMT_TIMEOUT:-6s}"      # statement_timeout de Postgres
PSQL_LOCK_TIMEOUT="${PSQL_LOCK_TIMEOUT:-2s}"      # lock_timeout de Postgres

[[ "${DEBUG}" == "true" ]] && set -x

# ---------- Pre-reqs ----------
command -v jq >/dev/null 2>&1      || { echo "❌ jq no encontrado"; exit 1; }
command -v curl >/dev/null 2>&1    || { echo "❌ curl no encontrado"; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "❌ 'timeout' no encontrado"; exit 1; }

_hdr=(-H "$API_KEY_HEADER")
log() { echo -e "\033[36m[SMOKE]\033[0m $*"; }
ok()  { echo -e "\033[32m[ OK ]\033[0m $*"; }
ko()  { echo -e "\033[31m[FAIL]\033[0m $*"; exit 1; }

# ---------- Helpers ----------
normalize_api_base() {
  local base="${API_BASE%/}" code
  code=$(curl -sS -o /dev/null -w "%{http_code}" "${_hdr[@]}" "$base/health" || true)
  if [[ "$code" == "200" ]]; then API_BASE="$base"; return; fi
  code=$(curl -sS -o /dev/null -w "%{http_code}" "${_hdr[@]}" "$base/v1/health" || true)
  if [[ "$code" == "200" ]]; then API_BASE="$base/v1"; return; fi
  API_BASE="$base"
}

psql_val() {
  local q="$1"
  ${DC} exec -T db psql -U ispuser -d ispdb -tA -v ON_ERROR_STOP=1 -c "$q" | tr -d '\r'
}

exec_db() {
  local sql="$1"
  local stmt="
    SET lock_timeout = '${PSQL_LOCK_TIMEOUT}';
    SET statement_timeout = '${PSQL_STMT_TIMEOUT}';
    ${sql}
  "
  if [[ -z "${PSQL_TIMEOUT:-}" || "${PSQL_TIMEOUT}" == "0" || "${PSQL_TIMEOUT}" == "0s" ]]; then
    ${DC} exec -T db psql -U ispuser -d ispdb -X -q -v ON_ERROR_STOP=1 -c "${stmt}"
    return
  fi
  if ! timeout --preserve-status --kill-after=5s "${PSQL_TIMEOUT}" \
        ${DC} exec -T db psql -U ispuser -d ispdb -X -q -v ON_ERROR_STOP=1 -c "${stmt}"; then
    echo "⚠️  exec_db con timeout falló; reintentando sin timeout…" >&2
    ${DC} exec -T db psql -U ispuser -d ispdb -X -q -v ON_ERROR_STOP=1 -c "${stmt}"
  fi
}

# --- SQL blocks ---
consistency_diffs_sql() {
  cat <<'SQL'
WITH
ing AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
egr AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ap  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
an  AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ti  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
to2 AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr  USING (almacen_id, material_id)
  FULL JOIN ap   USING (almacen_id, material_id)
  FULL JOIN an   USING (almacen_id, material_id)
  FULL JOIN ti   USING (almacen_id, material_id)
  FULL JOIN to2  USING (almacen_id, material_id)
)
SELECT COUNT(*)::int
FROM tot t
LEFT JOIN public.stock_almacen sa USING (almacen_id, material_id)
WHERE COALESCE(sa.cantidad,0) <> t.teorica;
SQL
}

diagnose_sql_material() {
  local mat="$1"
  cat <<SQL
WITH
ing AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
egr AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ap  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
an  AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ti  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
to2 AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m
        WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr  USING (almacen_id, material_id)
  FULL JOIN ap   USING (almacen_id, material_id)
  FULL JOIN an   USING (almacen_id, material_id)
  FULL JOIN ti   USING (almacen_id, material_id)
  FULL JOIN to2  USING (almacen_id, material_id)
)
SELECT a.codigo, t.material_id, COALESCE(sa.cantidad,0) AS real, t.teorica,
       (COALESCE(sa.cantidad,0)-t.teorica) AS delta
FROM tot t
LEFT JOIN public.stock_almacen sa USING (almacen_id, material_id)
JOIN public.almacenes a ON a.id = t.almacen_id
WHERE COALESCE(sa.cantidad,0) <> t.teorica
  AND t.material_id = ${mat}
ORDER BY ABS(COALESCE(sa.cantidad,0)-t.teorica) DESC, a.codigo;
SQL
}

autorepair_preview_sql() {
  cat <<'SQL'
WITH
ing AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
egr AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ap  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
an  AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ti  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
to2 AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    (COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0))::int AS cantidad
  FROM ing FULL JOIN egr USING (almacen_id, material_id)
           FULL JOIN ap  USING (almacen_id, material_id)
           FULL JOIN an  USING (almacen_id, material_id)
           FULL JOIN ti  USING (almacen_id, material_id)
           FULL JOIN to2 USING (almacen_id, material_id)
)
SELECT COUNT(*) AS rows_to_write,
       SUM((cantidad<0)::int) AS negatives
FROM tot;
SQL
}

autorepair_apply_sql() {
  cat <<'SQL'
BEGIN;
CREATE TEMP TABLE bak_stock AS TABLE public.stock_almacen;
TRUNCATE TABLE public.stock_almacen;
WITH
ing AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
egr AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ap  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
an  AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
ti  AS (SELECT m.to_almacen_id  AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL GROUP BY 1,2),
to2 AS (SELECT m.from_almacen_id AS almacen_id, m.material_id, SUM(m.cantidad)::int AS qty
        FROM public.movimientos m WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL GROUP BY 1,2),
tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    (COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0))::int AS cantidad
  FROM ing FULL JOIN egr USING (almacen_id, material_id)
           FULL JOIN ap  USING (almacen_id, material_id)
           FULL JOIN an  USING (almacen_id, material_id)
           FULL JOIN ti  USING (almacen_id, material_id)
           FULL JOIN to2 USING (almacen_id, material_id)
)
INSERT INTO public.stock_almacen(almacen_id, material_id, cantidad)
SELECT almacen_id, material_id, GREATEST(cantidad,0)
FROM tot
WHERE cantidad IS NOT NULL;
COMMIT;
SQL
}

kardex_has_note() {
  local note="$1"
  local count
  count=$(curl -sS "${_hdr[@]}" "${API_BASE}/inventario/kardex?limit=20" \
          | jq "map(select(.materialId==${MAT_ID} and .nota==\"${note}\")) | length")
  [[ "$count" =~ ^[0-9]+$ ]] || echo 0
  echo "$count"
}

check_consistency_or_diagnose() {
  local CONSIST_RETRIES=5 attempt=1 diffs=0
  while (( attempt <= CONSIST_RETRIES )); do
    diffs=$(psql_val "$(consistency_diffs_sql)")
    [[ "$diffs" == "0" ]] && return 0
    sleep 0.4; (( attempt++ ))
  done
  echo
  echo "── Diagnóstico de diferencias:"
  ${DC} exec -T db psql -U ispuser -d ispdb -c "$(diagnose_sql_material "${MAT_ID}")" || true
  echo
  echo "── Últimos 6 movimientos del material ${MAT_ID}:"
  ${DC} exec -T db psql -U ispuser -d ispdb -c "SELECT id, tipo, cantidad, from_almacen_id, to_almacen_id, nota, fecha FROM public.movimientos WHERE material_id=${MAT_ID} ORDER BY fecha DESC LIMIT 6;" || true
  return 1
}

auto_repair_if_needed() {
  local diffs="$1"
  [[ "${diffs}" == "0" ]] && return 0
  [[ "${AUTO_REPAIR_STOCK}" != "true" ]] && return 1

  if [[ "${AUTO_REPAIR_PREVIEW}" == "true" ]]; then
    log "Auto-repair (preview): estimando filas a reescribir…"
    ${DC} exec -T db psql -U ispuser -d ispdb -c "$(autorepair_preview_sql)" || true
  fi

  if [[ "${AUTO_REPAIR_CONFIRM}" != "true" ]]; then
    echo "⚠️  AUTO_REPAIR_CONFIRM=false → no se aplica reparación automática (solo preview)."
    return 1
  fi

  echo
  log "Auto-repair: reconstruyendo stock_almacen desde movimientos (con backup TEMP)…"
  ${DC} exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "$(autorepair_apply_sql)"
  ok "Rebuild de stock_almacen completado"

  local diffs2
  diffs2=$(psql_val "$(consistency_diffs_sql)")
  if [[ "${diffs2}" == "0" ]]; then
    ok "Consistencia verificada después del auto-repair (diffs=0)."
    return 0
  fi
  echo
  ko "Persisten diferencias tras auto-repair (diffs=${diffs2})."
}

# ---------- Paso 0: limpieza opcional ----------
if [[ "${CLEAN}" == "true" ]]; then
  log "Limpieza opcional de kardex (timeout ${PSQL_TIMEOUT})…"
  set +e
  if exec_db "DELETE FROM public.movimientos WHERE tipo='ajuste' AND cantidad=999999 AND nota='rechazo-saldo';"; then
    ok "Kardex limpio (si había registros)."
  else
    echo "⚠️  Limpieza expiró o falló (posible lock). Continuando sin detener smoke…"
  fi
  set -e
else
  log "Limpieza opcional DESACTIVADA (CLEAN=true para habilitarla)."
fi

# ---------- Paso 1: readiness ----------
normalize_api_base
log "Esperando readiness en ${API_BASE}/health …"
ready="false"
for i in $(seq 1 "${READINESS_TRIES}"); do
  code=$(curl -sS -o /dev/null -w "%{http_code}" "${_hdr[@]}" "${API_BASE}/health" || true)
  echo "  try#${i} -> /health => ${code}"
  if [[ "${code}" == "200" ]]; then ready="true"; break; fi
  sleep 1
done
[[ "${ready}" == "true" ]] || ko "API no lista tras ${READINESS_TRIES}s"
ok "API lista."

# ---------- Paso 2: sonda kardex ----------
log "Sonda kardex…"
curl -sS "${_hdr[@]}" "${API_BASE}/inventario/kardex?limit=1" | jq -e '.[0]' >/dev/null \
  || ko "Kardex no devolvió JSON esperado"
ok "Kardex responde JSON."

# ---------- Paso 3: 409 esperado ----------
log "Forzando ajuste (-999999) debe responder 409/INSUFFICIENT_STOCK y NO escribir kardex…"
resp=$(curl -sS -w "\n%{http_code}\n" "${_hdr[@]}" -H "content-type: application/json" \
  -d "{\"materialId\":${MAT_ID},\"cantidad\":999999,\"signo\":\"menos\",\"nota\":\"rechazo-saldo\"}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/ajustar")
body="$(echo "${resp}" | sed '$d')"
code="$(echo "${resp}" | tail -n1)"
[[ "${code}" == "409" ]] || { echo "${body}"; ko "Esperaba HTTP 409 y recibí ${code}"; }
echo "${body}" | jq -e '.code=="INSUFFICIENT_STOCK"' >/dev/null || { echo "${body}"; ko "Falta code=INSUFFICIENT_STOCK"; }

has_rechazo=$(curl -sS "${_hdr[@]}" "${API_BASE}/inventario/kardex?limit=${KARDEX_LIMIT}" | jq 'map(select(.nota=="rechazo-saldo")) | length')
[[ "${has_rechazo}" == "0" ]] || ko "Se encontró 'rechazo-saldo' en kardex (no debería)."
ok "Rechazo por saldo correcto (409) y kardex limpio."

# ---------- Paso 4: +2 / -2 ----------
log "Ajuste +2 y revertir -2 en TEC-${TECH_ID} / material ${MAT_ID}…"
base=$(curl -sS "${_hdr[@]}" "${API_BASE}/inventario/tecnicos/${TECH_ID}/stock" | jq "map(select(.material_id==${MAT_ID}))[0].cantidad")
[[ "${base}" =~ ^[0-9]+$ ]] || ko "Stock base inválido: ${base}"

curl -sS "${_hdr[@]}" -H "content-type: application/json" \
  -d "{\"materialId\":${MAT_ID},\"cantidad\":2,\"signo\":\"mas\",\"nota\":\"smoke (+2)\"}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/ajustar" | jq -e '.ok==true' >/dev/null || ko "Fallo ajuste +2"

post=$(curl -sS "${_hdr[@]}" "${API_BASE}/inventario/tecnicos/${TECH_ID}/stock" | jq "map(select(.material_id==${MAT_ID}))[0].cantidad")
[[ "${post}" == $((base+2)) ]] || ko "Esperaba $((base+2)) tras +2, obtuve ${post}"

curl -sS "${_hdr[@]}" -H "content-type: application/json" \
  -d "{\"materialId\":${MAT_ID},\"cantidad\":2,\"signo\":\"menos\",\"nota\":\"smoke revert (-2)\"}" \
  "${API_BASE}/inventario/tecnicos/${TECH_ID}/ajustar" | jq -e '.ok==true' >/dev/null || ko "Fallo revert -2"

final=$(curl -sS "${_hdr[@]}" "${API_BASE}/inventario/tecnicos/${TECH_ID}/stock" | jq "map(select(.material_id==${MAT_ID}))[0].cantidad")
[[ "${final}" == "${base}" ]] || ko "Esperaba volver a ${base}, obtuve ${final}"
ok "Ciclo +2/-2 correcto."

# ---------- Paso 5: traslado ida/vuelta (por función SQL) ----------
log "Traslado CENTRAL -> TEC-${TECH_ID} y reversa…"
CENTRAL_ID="$(psql_val "SELECT id FROM public.almacenes WHERE codigo='CENTRAL' LIMIT 1;")"
TEC_ID="$(psql_val "SELECT id FROM public.almacenes WHERE codigo='TEC-${TECH_ID}' LIMIT 1;")"
[[ -n "${CENTRAL_ID}" && -n "${TEC_ID}" ]] || ko "No pude resolver IDs de almacenes"

has_central="$(psql_val "SELECT COALESCE((SELECT cantidad FROM public.stock_almacen WHERE almacen_id='${CENTRAL_ID}' AND material_id=${MAT_ID}),0);")"
if [[ "${has_central}" -lt 1 ]]; then
  exec_db "INSERT INTO public.movimientos (tipo, material_id, cantidad, to_almacen_id, fecha, nota)
           VALUES ('ajuste', ${MAT_ID}, 1, '${CENTRAL_ID}', now(), 'preload smoke inventory');"
fi

exec_db "SELECT public.fn_mov_traslado('${CENTRAL_ID}', '${TEC_ID}', ${MAT_ID}, 1, 'smoke traslado ida');"
sleep 0.2
[[ "$(kardex_has_note 'smoke traslado ida')" -ge 1 ]] || ko "No se reflejó kardex de ida"

exec_db "SELECT public.fn_mov_traslado('${TEC_ID}', '${CENTRAL_ID}', ${MAT_ID}, 1, 'smoke traslado vuelta');"
sleep 0.2
[[ "$(kardex_has_note 'smoke traslado vuelta')" -ge 1 ]] || ko "No se reflejó kardex de vuelta"

# ---------- Paso 6: consistencia + métricas CI ----------
log "Verificando consistencia movimientos vs stock…"
diffs=$(psql_val "$(consistency_diffs_sql)")
if [[ "${diffs}" != "0" ]]; then
  if ! check_consistency_or_diagnose; then
    if auto_repair_if_needed "${diffs}"; then
      ok "Todos los smokes pasaron ✨"
      diffs="0"
    else
      ko "Diferencias entre stock_almacen y movimientos (ver diagnóstico arriba)."
    fi
  fi
fi

# Métrica (útil en CI)
echo "inventory_diffs=${diffs}"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Inventory smoke"
    echo "- diffs: \`${diffs}\`"
    echo "- tech: \`${TECH_ID}\`, material: \`${MAT_ID}\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi

ok "Consistencia verificada (diffs=0)."
ok "Todos los smokes pasaron ✨"
