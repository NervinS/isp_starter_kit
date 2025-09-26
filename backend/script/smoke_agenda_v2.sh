#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== 📅 Smoke Agenda (v2) ==="
cd "$(dirname "$0")" && echo "📁 CWD: $PWD"
API="http://127.0.0.1:3000/v1"
psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

for i in {1..90}; do curl -fsS "$API/health" >/dev/null && break || sleep 1; done
curl -fsS "$API/health" >/dev/null || { echo "❌ API no respondió /v1/health"; exit 1; }

need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ falta binario: $1"; exit 1; }; }
need_bin jq
need_bin curl

TEC_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
USR_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;" | tr -d '\r')"
[ -n "$TEC_ID" ] && [ -n "$USR_ID" ] || { echo "❌ faltan TEC/USR"; exit 1; }

# elegir motivo
CAT="$(curl -fsS "$API/catalogos/motivos-reagenda" || true)"
MCODE="$( echo "$CAT" | jq -r '[.items[]?.codigo] | if index("cliente-ausente") then "cliente-ausente" else .[0] end' 2>/dev/null || echo "")"
[ -n "$MCODE" ] || MCODE="cliente-ausente"

# crear por SQL
STAMP="$(date +%y%m%d%H%M%S)"
COD="INS-$STAMP"
$psqlq "INSERT INTO ordenes (id,usuario_id,tipo,codigo,estado) VALUES (gen_random_uuid(),'$USR_ID','INS','$COD','creada');" >/dev/null

TOMORROW="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
DAY2="$(date -u -d '+2 day' +%F 2>/dev/null || date -u -v+2d +%F)"

call() {
  local method="$1" url="$2" data="${3-}" http body
  if [[ -n "${data:-}" ]]; then
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" -H 'Content-Type: application/json' -d "$data" || true)"
  else
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" || true)"
  fi
  body="$(cat /tmp/_body)"
  if [[ "$http" -ge 400 || -z "$http" ]]; then
    echo "❌ $method $url -> HTTP $http"
    printf '%s\n' "$body" | sed -n '1,120p'
    exit 1
  fi
  printf '%s\n' "$body"
}

echo "== asignar =="
call POST "$API/agenda/ordenes/$COD/asignar" "$(jq -nc --arg f "$TOMORROW" --arg t am --arg tech "$TEC_ID" '{fecha:$f,turno:$t,tecnicoId:$tech}')" | jq . || true

echo "== reagendar =="
call POST "$API/agenda/ordenes/$COD/reagendar" "$(jq -nc --arg f "$DAY2" --arg t pm --arg mc "$MCODE" --arg m 'Cliente reprograma' '{fecha:$f,turno:$t,motivoCodigo:$mc,motivo:$m}')" | jq . || true

echo "== cancelar =="
call POST "$API/agenda/ordenes/$COD/cancelar" | jq . || true

echo "== anular =="
call POST "$API/agenda/ordenes/$COD/anular" "$(jq -nc --arg m 'Cliente desistió' --arg mc "$MCODE" '{motivo:$m,motivoCodigo:$mc}')" | jq . || true

echo "🎉 Smoke Agenda v2 OK"
