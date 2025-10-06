#!/usr/bin/env bash
# script/smoke_all.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"

say() { echo -e "$@"; }

# --- Health gate --------------------------------------------------------------
say "=== 🧪 Smoke ALL (gate de health) ==="
say "API_BASE=${API_BASE}  KEY=${KEY}"
say "⏳ Esperando API en ${API_BASE}…"
for i in {1..60}; do
  if curl -sf -H "x-api-key: ${KEY}" "${API_BASE}/v1/health" >/dev/null; then break; fi
  sleep 1
done
health=$(curl -s -H "x-api-key: ${KEY}" "${API_BASE}/v1/health" \
  | jq -r '(.ok // .status // "unknown") | if . == true then "ok" elif . == false then "fail" else . end' || true)
say "Health => ${health}"
if [[ "${health}" != "ok" ]]; then
  echo "❌ API no saludable (health=${health}). Abortando." >&2
  exit 1
fi

# --- Runner util --------------------------------------------------------------
pass=()
fail=()

run_step() {
  local name="$1"
  local cmd="$2"
  say "\n--- ▶ ${name} ---"
  # shellcheck disable=SC2086
  if bash -lc "${cmd}"; then
    say "✅ ${name} OK"
    pass+=("${name}")
  else
    code=$?
    say "❌ ${name} FAIL (exit ${code})"
    fail+=("${name}")
  fi
}

# --- Secuencia (sin desviarnos del checklist) --------------------------------
# Orden sugerido: mínimos → packs → agenda → inventario (traslado & full) → cierres
run_step "smoke_tecnicos_min"           "./script/smoke_tecnicos_min.sh"
run_step "smoke_inventario_min"         "./script/smoke_inventario_min.sh"
run_step "smoke_kardex_min"             "./script/smoke_kardex_min.sh"

# pack básico que ya orquesta algunos mínimos
run_step "smoke (pack básicos)"         "./script/smoke.sh"

# agenda (compacto y verbose)
run_step "smoke_agenda"                 "./script/smoke_agenda.sh"
run_step "smoke_agenda_verbose"         "./script/smoke_agenda_verbose.sh"

# inventario (traslado dirigido y pruebas inventory más completas)
run_step "smoke_inventario_traslado"    "./script/smoke_inventario_traslado.sh"

# ← IMPORTANTE: deshabilitamos timeout externo y activamos autorepair para este paso
run_step "smoke_inventory"              "PSQL_TIMEOUT=0s CLEAN=true AUTO_REPAIR_STOCK=true ./script/smoke_inventory.sh"

# cierre de equipos/ordenes
run_step "smoke_ins_equipos_cierre"     "./script/smoke_ins_equipos_cierre.sh"

# --- Consistency check rápido (reporte humano + exit code) --------------------
# NUEVO: integración directa del reconcilio simple
run_step "reconcile_inventory"          "./script/reconcile_inventory.sh"

# --- Consistency check estricto ----------------------------------------------
say "\n=== 🔎 Consistency Check (stock vs movimientos) ==="
# Ejecuta el reporte humano y, además, evalúa el número de diffs para determinar exit code.
report_out="$(./script/db_consistency_check.sh || true)"
echo "${report_out}"

# Intenta extraer el número de diferencias desde el bloque "=== Resumen: ..." (línea ' diffs' seguida del número)
diffs="$(echo "${report_out}" | awk '/^ diffs$/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0}' || echo "")"
# Si no lo encontró, no asumas OK; fuerza una consulta compacta dentro del contenedor:
if [[ -z "${diffs}" ]]; then
  diffs="$(docker compose exec -T db bash -lc "
psql -U ispuser -d ispdb -At <<'SQL'
WITH ing AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), egr AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ap AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), an AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ti AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), to2 AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr USING (almacen_id, material_id)
  FULL JOIN ap  USING (almacen_id, material_id)
  FULL JOIN an  USING (almacen_id, material_id)
  FULL JOIN ti  USING (almacen_id, material_id)
  FULL JOIN to2 USING (almacen_id, material_id)
), diffs AS (
  SELECT 1
  FROM tot t
  LEFT JOIN stock_almacen s USING (almacen_id, material_id)
  JOIN almacenes a ON a.id = t.almacen_id
  WHERE COALESCE(s.cantidad,0) <> t.teorica
)
SELECT COALESCE(count(*),0) FROM diffs;
SQL
" | tr -d '\r')"
fi

diffs="${diffs:-0}"
if [[ ! "${diffs}" =~ ^[0-9]+$ ]]; then
  echo "⚠️  No se pudo parsear 'diffs' (${diffs}). Continúo pero marco el paso como sospechoso."
  fail+=("consistency_check_parse")
else
  if (( diffs > 0 )); then
    echo "❌ Consistency check encontró ${diffs} diferencias. Ver reporte arriba."
    fail+=("consistency_check_${diffs}")
  else
    echo "✅ Consistency check OK (diffs=0)"
    pass+=("consistency_check")
  fi
fi

# --- Resumen ------------------------------------------------------------------
say "\n=== 📋 Resumen ==="
echo "✅ PASS: ${#pass[@]} -> ${pass[*]-}"
echo "❌ FAIL: ${#fail[@]} -> ${fail[*]-}"

[[ ${#fail[@]} -eq 0 ]]
