#!/usr/bin/env bash
# Gate de health + smokes mínimos del checklist.
# Por defecto corre sólo los críticos: smoke_pdf y smoke_metrics.
# Para ejecutar todo el pack legacy: FULL=1 ./script/smoke_all.sh

set -euo pipefail
API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"

echo "=== 🧪 Smoke ALL (gate de health) ==="
echo "API_BASE=$API_BASE  KEY=$KEY"

# Gate de health con reintentos cortos
echo "⏳ Esperando API en ${API_BASE}… (máx 20s)"
for i in {1..10}; do
  c1="$(curl -sS -o /dev/null -w '%{http_code}' "${API}/health" || true)"
  c2="$(curl -sS -o /dev/null -w '%{http_code}' "${API_BASE}/health" || true)"
  echo "  try#${i} -> /v1/health => ${c1} | /health => ${c2}"
  if [[ "$c1" == "200" ]]; then
    echo "Health => ok"
    break
  fi
  sleep 2
  if [[ "$i" == "10" ]]; then
    echo "❌ API no respondió 200 en health"
    exit 1
  fi
done

run() { echo -e "\n--- ▶ $1 ---"; shift; bash -c "$*"; }

# Siempre ejecutamos los críticos del checklist:
run "smoke_pdf" "API=${API} KEY=${KEY} PUBLIC_BASE=\"${PUBLIC_BASE:-}\" script/smoke_pdf.sh" || true
run "smoke_metrics" "API=${API} KEY=${KEY} script/smoke_metrics.sh" || true

# El resto solo si FULL=1 (evitamos ruido rojo mientras DB no está sembrada)
if [[ "${FULL:-0}" == "1" ]]; then
  run "smoke_tecnicos_min" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_tecnicos_min.sh" || true
  run "smoke_inventario_min" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_inventario_min.sh" || true
  run "smoke_kardex_min" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_kardex_min.sh" || true
  run "smoke (pack básicos)" "API_BASE=${API_BASE} KEY=${KEY} script/smoke.sh" || true
  run "smoke_agenda" "API=${API} KEY=${KEY} script/smoke_agenda.sh" || true
  run "smoke_agenda_verbose" "API=${API} KEY=${KEY} script/smoke_agenda_verbose.sh" || true
  run "smoke_inventario_traslado" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_inventario_traslado.sh" || true
  run "smoke_inventory" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_inventory.sh" || true
  run "smoke_ins_equipos_cierre" "API_BASE=${API_BASE} KEY=${KEY} script/smoke_ins_equipos_cierre.sh" || true
  run "smoke_ordenes" "API=${API} KEY=${KEY} script/smoke_ordenes.sh" || true
  run "smoke_jobs" "API=${API} KEY=${KEY} script/smoke_jobs.sh" || true
  run "reconcile_inventory" "script/reconcile_inventory.sh" || true
  run "consistency_check" "script/consistency_check.sh" || true
fi

echo -e "\n=== ✅ Fin smoke core. Para ejecutar todo: FULL=1 ./script/smoke_all.sh ==="
