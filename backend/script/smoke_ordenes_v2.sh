#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== 🚦 Smoke Órdenes (v2) ==="
cd "$(dirname "$0")" && echo "📁 CWD: $PWD"

API="http://127.0.0.1:3000/v1"
psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

docker compose up -d db api >/dev/null

echo "⏳ Esperando API..."
for i in {1..90}; do
  if curl -fsS "$API/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS "$API/health" >/dev/null || { echo "❌ API no respondió /v1/health tras 90s"; exit 1; }

need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ falta binario: $1"; exit 1; }; }
need_bin jq
need_bin curl

TEC_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
USR_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;" | tr -d '\r')"
[ -n "$TEC_ID" ] && [ -n "$USR_ID" ] || { echo "❌ faltan TEC/USR"; exit 1; }

# helper curl que NO tumba el script si el body no es JSON
call() {
  local method="$1" url="$2" data="${3-}" rc body http
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

# === CORTE (simulado): crea por SQL una orden COR agendada y ciérrala por /tecnicos
STAMP="$(date +%y%m%d%H%M%S)"
ORD_COR="COR-$STAMP"
$psqlq "INSERT INTO ordenes (id,usuario_id,tipo,codigo,estado) VALUES (gen_random_uuid(),'$USR_ID','COR','$ORD_COR','agendada');" >/dev/null

call POST "$API/agenda/ordenes/$ORD_COR/asignar" "$(jq -nc --arg f "$(date -u +%F)" --arg t am --arg tech "$TEC_ID" '{fecha:$f,turno:$t,tecnicoId:$tech}')"
call POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$ORD_COR/iniciar" '{}'
CLOSE_COR="$(call POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$ORD_COR/cerrar" '{"materiales":[],"evidenciasBase64":[]}' | jq -r '.estado // .orden.estado // empty' 2>/dev/null || true)"
[[ "$CLOSE_COR" == "cerrada" ]] || { echo "❌ COR no cerrada (estado=$CLOSE_COR)"; exit 1; }
echo "✅ COR cerrada: $ORD_COR"

# === MAN: crear + cerrar con payload extendido
ORD_MAN="MAN-$STAMP"
$psqlq "INSERT INTO ordenes (id,usuario_id,tipo,codigo,estado) VALUES (gen_random_uuid(),'$USR_ID','MAN','$ORD_MAN','creada');" >/dev/null
TOMORROW="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
call POST "$API/agenda/ordenes/$ORD_MAN/asignar" "$(jq -nc --arg f "$TOMORROW" --arg t am --arg tech "$TEC_ID" '{fecha:$f,turno:$t,tecnicoId:$tech}')"
call POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$ORD_MAN/iniciar" '{}'

PIXEL="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFygJp2k1gWQAAAABJRU5ErkJggg=="
PAY_CLOSE="$(jq -nc --arg p "$PIXEL" '{
  materiales:[{materialIdInt:3,cantidad:1}],
  firmaBase64:$p,
  evidenciasBase64:[$p,$p]
}')"
RESP="$(call POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$ORD_MAN/cerrar" "$PAY_CLOSE")"
echo "$RESP" | jq . || true
EST="$(echo "$RESP" | jq -r '.estado // .orden.estado // empty' 2>/dev/null || true)"
[[ "$EST" == "cerrada" ]] || { echo "❌ MAN no cerrada (estado=$EST)"; exit 1; }

echo "✅ MAN cerrada: $ORD_MAN"
echo "🎉 Smoke Órdenes v2 OK"
