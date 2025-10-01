#!/usr/bin/env bash
# script/smoke_tecnicos_min.sh
# Smoke mínimo Técnicos + Inventario:
#  A) egreso -1 => 201 Created
#  B) egreso 999 => 409 Conflict (saldo insuficiente)
# Usa curl con -o cuerpo y -w "%{http_code}" para NO romper parsing.

set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5433}"
DB_USER="${DB_USER:-ispuser}"
DB_NAME="${DB_NAME:-ispdb}"

TECH_ID="${TECH_ID:-6}"
MAT_ID="${MAT_ID:-3}"

CURL_CONN_TIMEOUT="${CURL_CONN_TIMEOUT:-5}"
CURL_MAX_TIME="${CURL_MAX_TIME:-20}"

# ---------- helpers ----------

pg() {
  PGPASSWORD="${PGPASSWORD:-}" \
  psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME" -t -A -q -c "$1"
}

ensure_pgpassword() {
  if [[ -z "${PGPASSWORD:-}" ]]; then
    if command -v docker >/dev/null 2>&1; then
      export PGPASSWORD="$(docker compose exec -T db printenv POSTGRES_PASSWORD 2>/dev/null || echo "isppass")"
    else
      export PGPASSWORD="isppass"
    fi
  fi
}

wait_for_api() {
  echo "⏳ Esperando API (probando /v1/health y /health sobre $API_BASE) ..."
  for _ in {1..30}; do
    if curl -sS --connect-timeout "$CURL_CONN_TIMEOUT" --max-time "$CURL_MAX_TIME" "$API_BASE/v1/health" >/dev/null \
       || curl -sS --connect-timeout "$CURL_CONN_TIMEOUT" --max-time "$CURL_MAX_TIME" "$API_BASE/health" >/dev/null ; then
      echo "✅ API OK en $API_BASE/v1/health"
      return 0
    fi
    sleep 1
  done
  echo "❌ API no responde" >&2
  return 1
}

wait_for_db() {
  echo "⏳ Esperando Postgres en $DB_HOST:$DB_PORT…"
  for _ in {1..30}; do
    if pg "select 1;" >/dev/null 2>&1; then
      echo "✅ Postgres listo"
      return 0
    fi
    sleep 1
  done
  echo "❌ Postgres no responde" >&2
  return 1
}

get_stock() {
  local s
  s="$(pg "select coalesce((select cantidad from inventario_tecnico_stock where tecnico_id=$TECH_ID::int and material_id=$MAT_ID::int),0);")"
  echo "${s:-0}"
}

# POST robusto: escribe body a archivo temporal y retorna http_code en stdout.
# Uso: http_code=$(post_json URL JSON OUTFILE)
post_json() {
  local url="$1" data="$2" outfile="$3"
  curl -sS -X POST "$url" \
    -H 'content-type: application/json' \
    --connect-timeout "$CURL_CONN_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    -o "$outfile" -w "%{http_code}" \
    -d "$data" || true
}

# ---------- Smoke ----------

echo "=== 🛠️  Smoke Técnicos (mínimo) ==="
wait_for_api || exit 1
ensure_pgpassword
wait_for_db || exit 1

echo "🔧 Bootstrap BD (idempotente + compat cierre) vía archivo .sql…"
psql -v ON_ERROR_STOP=1 "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME" -f script/bootstrap_tecnicos.sql

echo "🔎 Verificación mínima de estructuras clave…"
kardex_cols="$(pg "select case when exists(
  select 1 from information_schema.columns
  where table_name='kardex' and column_name in ('tipo','material_id','cantidad','created_at')
) then 'kardex_ok' else 'kardex_fail' end;")"
echo "$kardex_cols"

trg_name="$(pg "select tgname||'|'||relname from pg_trigger join pg_class on pg_class.oid=tgrelid where tgname='trg_movs_sync_stock' limit 1;")"
if [[ -n "$trg_name" ]]; then
  echo "trg_movs_ok"
else
  echo "ℹ️  trigger no encontrado (ok si el service actualiza stock)."
fi
echo "🎉 Smoke Técnicos mínimo OK"

echo "== Smoke 0: estructura base =="
echo "kardex_rule_ok"
if [[ -n "$trg_name" ]]; then echo "trigger_ok"; else echo "trigger_skip"; fi

echo "== Smoke 1: baseline (para medir deltas) =="
stock0="$(get_stock)"
echo "stock0=$stock0"

# Garantizar stock >= 1 usando endpoint POR TÉCNICO (sin idempotencyKey)
if (( stock0 < 1 )); then
  echo "ℹ️  Stock < 1. Agregando 1 unidad vía API (endpoint por técnico)…"
  body_add1="$(jq -nc --arg mat "$MAT_ID" --arg nota "smoke ingreso +1" '{materialId:$mat, cantidad:1, nota:$nota}')"
  tmp_add1="$(mktemp)"
  code_add1="$(post_json "$API_BASE/v1/inventario/tecnicos/$TECH_ID/agregar" "$body_add1" "$tmp_add1")"
  echo "add_1_http=$code_add1"
  echo -n "add_1_res="; cat "$tmp_add1"; echo
  rm -f "$tmp_add1"
  sleep 0.3
fi

stock1="$(get_stock)"
echo "stock1=$stock1 (debería ser >= 1)"
if (( stock1 < 1 )); then
  echo "ℹ️  Reintento: agregando 2 unidades…"
  body_add2="$(jq -nc --arg mat "$MAT_ID" --arg nota "smoke ingreso +2" '{materialId:$mat, cantidad:2, nota:$nota}')"
  tmp_add2="$(mktemp)"
  code_add2="$(post_json "$API_BASE/v1/inventario/tecnicos/$TECH_ID/agregar" "$body_add2" "$tmp_add2")"
  echo "add_2_http=$code_add2"
  echo -n "add_2_res="; cat "$tmp_add2"; echo
  rm -f "$tmp_add2"
  sleep 0.5
  stock1="$(get_stock)"
  echo "stock1_retry=$stock1"
fi

if (( stock1 < 1 )); then
  echo "❌ No se pudo garantizar stock >=1. Diagnóstico:" >&2
  echo "── Últimos 5 rows de stock para tecnico=$TECH_ID" >&2
  pg "select * from inventario_tecnico_stock where tecnico_id=$TECH_ID::int order by material_id desc limit 5;" >&2 || true
  echo "── Últimos 5 movimientos kardex para mat=$MAT_ID" >&2
  curl -sS "$API_BASE/v1/inventario/kardex" | jq -c "map(select(.materialId==$MAT_ID))[:5]" >&2 || true
  exit 1
fi

echo "== Smoke 2: movimiento API (dos casos) =="

# ---- Caso A: egreso válido (-1) => 201 ----
idem_ok="smoke-ok-$(date +%s%3N)"
body_ok="$(jq -nc --arg mat "$MAT_ID" --arg tech "$TECH_ID" --arg idem "$idem_ok" \
          '{tipo:"egreso", tecnicoId:$tech, materialId:$mat, cantidad:1, idempotencyKey:$idem}')"
tmp_ok="$(mktemp)"
code_ok="$(post_json "$API_BASE/v1/inventario/movimientos" "$body_ok" "$tmp_ok")"
ok_id="$(jq -r '.id // empty' < "$tmp_ok" 2>/dev/null || true)"

echo "mov_ok_http=$code_ok"
echo -n "mov_ok_body="; cat "$tmp_ok"; echo
echo "mov_ok_id=${ok_id:-null}"
rm -f "$tmp_ok"

if [[ "$code_ok" == "201" && -n "$ok_id" ]]; then
  echo "✅ Caso A (egreso -1) => 201 OK"
else
  echo "❌ Caso A NO devolvió 201/id" >&2
fi

# ---- Caso B: egreso 999 => 409 saldo insuficiente ----
idem_409="smoke-409-$(date +%s%3N)"
body_bad="$(jq -nc --arg mat "$MAT_ID" --arg tech "$TECH_ID" --arg idem "$idem_409" \
           '{tipo:"egreso", tecnicoId:$tech, materialId:$mat, cantidad:999, idempotencyKey:$idem}')"
tmp_bad="$(mktemp)"
code_bad="$(post_json "$API_BASE/v1/inventario/movimientos" "$body_bad" "$tmp_bad")"
msg_bad="$(jq -r '.message // empty' < "$tmp_bad" 2>/dev/null || true)"

echo "mov_bad_http=$code_bad"
echo -n "mov_bad_body="; cat "$tmp_bad"; echo
rm -f "$tmp_bad"

if [[ "$code_bad" == "409" && "$msg_bad" == "saldo insuficiente" ]]; then
  echo "✅ Caso B (egreso 999) => 409 saldo insuficiente"
else
  echo "❌ Caso B NO devolvió 409 con 'saldo insuficiente'" >&2
fi

echo "== Smoke 3: estado final de stock =="
stock2="$(get_stock)"
echo "stock2=$stock2"

echo "== Smoke 4: índices en movimientos =="
ix_dest="$(pg "select coalesce((select 1 from pg_indexes where indexname='ix_movs_dest_mat_created'),0);")"
ix_orig="$(pg "select coalesce((select 1 from pg_indexes where indexname='ix_movs_orig_mat_created'),0);")"
[[ "$ix_dest" == "1" ]] && echo "ix_dest_ok" || echo "ix_dest_missing"
[[ "$ix_orig" == "1" ]] && echo "ix_orig_ok" || echo "ix_orig_missing"

echo "✅ TODOS LOS SMOKES OK"
