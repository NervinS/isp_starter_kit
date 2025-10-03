#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"

# Helpers HTTP con API key consistente
curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  curl -fsSL -X "${method}" \
    -H "x-api-key: ${KEY}" \
    -H "Content-Type: application/json" \
    "${url}" "$@"
}
curl_get() {
  local url="$1"
  curl -fsSL -H "x-api-key: ${KEY}" "${url}"
}

echo "=== 🛠️  Smoke Técnicos (mínimo) ==="
echo "⏳ Esperando API (probando /v1/health y /health sobre ${API_BASE}) ..."
if curl_get "${API_BASE}/v1/health" >/dev/null 2>&1 || curl_get "${API_BASE}/health" >/dev/null 2>&1; then
  echo "✅ API OK en ${API_BASE}/v1/health"
else
  echo "❌ API no responde" >&2
  exit 1
fi

# ---------- Paso opcional: psql (se salta si no hay credenciales válidas) ----------
can_psql=0
PSQL_URI="host=127.0.0.1 port=${DB_PORT:-5432} user=${DB_USER:-ispuser} dbname=${DB_NAME:-ispdb} sslmode=disable connect_timeout=2"

echo "⏳ Intentando conexión directa a Postgres para checks opcionales…"
if psql "${PSQL_URI}" -c "select 1" >/dev/null 2>&1; then
  can_psql=1
  echo "✅ Conexión psql OK"
else
  echo "⚠️  No se pudo conectar por psql (se omiten pasos de BD; el smoke continúa por API)"
fi

if [[ $can_psql -eq 1 ]]; then
  echo "🔧 Bootstrap BD (idempotente + compat cierre) vía archivo .sql…"
  # -w = nunca preguntar password; si falla, que falle aquí y seguimos por API
  psql -v ON_ERROR_STOP=1 --no-password -w "${PSQL_URI}" -f script/bootstrap_tecnicos.sql || true

  echo "🔎 Verificación mínima de estructuras clave…"
  psql "${PSQL_URI}" <<'SQL' || true
select 'kardex_ok' where exists (select 1 from information_schema.tables where table_name='movimientos');
select 'trg_movs_ok' where exists (select 1 from pg_trigger where tgname='trg_movimientos_delta');
SQL

  echo "== Smoke 0: estructura base =="
  psql "${PSQL_URI}" <<'SQL' || true
select 'kardex_rule_ok';
select 'trigger_ok';
SQL
fi
# ---------- Fin psql opcional ----------

# Variables de prueba (vía API)
TECNICO_ID="${TECNICO_ID:-6}"
MAT_ID="${MAT_ID:-3}"

echo "== Smoke 1: baseline (por API) =="
stock0=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" | jq -r --arg mid "${MAT_ID}" '.[] | select(.materialId==($mid|tonumber)) | .cantidad // 0' || echo "0")
echo "stock0=${stock0}"

if [[ "${stock0}" -lt 1 ]]; then
  echo "ℹ️  Stock < 1. Agregando 1 unidad vía API (endpoint por técnico)…"
  add_1_res=$(curl_json POST "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 1}" || true)
  echo "add_1_res=${add_1_res}"
fi

stock1=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" | jq -r --arg mid "${MAT_ID}" '.[] | select(.materialId==($mid|tonumber)) | .cantidad // 0' || echo "0")
echo "stock1=${stock1} (debería ser >= 1)"

if [[ "${stock1}" -lt 1 ]]; then
  echo "ℹ️  Reintento: agregando 2 unidades…"
  add_2_res=$(curl_json POST "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/agregar" \
    --data "{\"materialId\": ${MAT_ID}, \"cantidad\": 2}" || true)
  echo "add_2_res=${add_2_res}"
  stock1=$(curl_get "${API_BASE}/v1/inventario/tecnicos/${TECNICO_ID}/stock" | jq -r --arg mid "${MAT_ID}" '.[] | select(.materialId==($mid|tonumber)) | .cantidad // 0' || echo "0")
  echo "stock1_retry=${stock1}"
fi

if [[ "${stock1}" -lt 1 ]]; then
  echo "❌ No se pudo garantizar stock >=1. Diagnóstico (por API):"
  echo "── Últimos 5 movimientos kardex para mat=${MAT_ID}"
  curl_get "${API_BASE}/v1/inventario/kardex" | jq --arg mid "${MAT_ID}" '[.[] | select(.materialId==($mid|tonumber))] | sort_by(.fecha) | reverse | .[:5]' || true
  exit 1
fi

echo "🎉 Smoke Técnicos mínimo OK"
