#!/usr/bin/env bash
set -Eeuo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
DB_USER="${POSTGRES_USER:-ispuser}"
DB_NAME="${POSTGRES_DB:-ispdb}"

wait_for_health() {
  local tries="${1:-120}"
  echo "▶ Health"
  for i in $(seq 1 "$tries"); do
    if curl -fsS "$API_BASE/v1/health" >/dev/null; then echo "✓ API OK"; return 0; fi
    sleep 1
  done
  echo "✗ API no respondió /v1/health" >&2; exit 1
}

rid_logs() {
  local rid="$1"; [ -z "$rid" ] && return 0
  echo "— logs por RID —"
  docker compose logs --no-log-prefix api | sed -n "/$rid/,+120p" || true
}

resolve_tecnicos_base() {
  local tecid="$1"
  local c1="$API_BASE/v1/tecnicos/$tecid/pendientes"
  local c2="$API_BASE/v1/v1/tecnicos/$tecid/pendientes"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$c1")"
  [ "$code" != "404" ] && { echo "$API_BASE/v1/tecnicos"; return; }
  code="$(curl -s -o /dev/null -w '%{http_code}' "$c2")"
  [ "$code" != "404" ] && { echo "$API_BASE/v1/v1/tecnicos"; return; }
  echo "$API_BASE/v1/tecnicos"
}

wait_for_health 120

echo "▶ Resolviendo TECID / OID / MOTIVO desde la DB"
TEC_ROW="$(docker compose exec -T db psql -At -U "$DB_USER" -d "$DB_NAME" \
  -c "select id,codigo from tecnicos where activo is true order by codigo limit 1;")"
TECID="${TEC_ROW%%|*}"; TECCODE="${TEC_ROW##*|}"

OID_ROW="$(docker compose exec -T db psql -At -U "$DB_USER" -d "$DB_NAME" \
  -c "select id,codigo from ordenes where estado <> 'cerrada' order by codigo limit 1;")"
OID_DB="$(cut -d'|' -f1 <<<"$OID_ROW")"; OID_CODE="$(cut -d'|' -f2 <<<"$OID_ROW")"

MOT_ROW="$(docker compose exec -T db psql -At -U "$DB_USER" -d "$DB_NAME" \
  -c "select id,codigo from motivos_reagenda order by codigo limit 1;")"
MOTIVO_ID="${MOT_ROW%%|*}"; MOTIVO_CODE="${MOT_ROW##*|}"

echo "✓ TECID=$TECID|$TECCODE  OID=$OID_DB|$OID_CODE  MOTIVO=$MOTIVO_ID|$MOTIVO_CODE"

echo "▶ Generando tokens"
ADMIN_TOKEN="$(docker compose exec -T api sh -lc \
"node -e 'const jwt=require(\"jsonwebtoken\");console.log(jwt.sign({sub:\"admin\",roles:[\"admin\"]},process.env.JWT_SECRET||\"dev\",{expiresIn:\"10m\"}));'")"
TEC_TOKEN="$(docker compose exec -T api sh -lc \
"node -e 'const jwt=require(\"jsonwebtoken\");console.log(jwt.sign({sub:\"tec\",roles:[\"tecnico\"],tecnicoId:\"$TECID\"},process.env.JWT_SECRET||\"dev\",{expiresIn:\"10m\"}));'")"
echo "✓ Tokens listos"

TEC_BASE="$(resolve_tecnicos_base "$TECID")"

echo "▶ Asignando $OID_CODE a $TECCODE (admin)"
TODAY="$(date +%F)"
RESP="$(curl -s -i -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"tecnicoId\":\"$TECID\",\"fecha\":\"$TODAY\",\"turno\":\"am\"}" \
  "$API_BASE/v1/agenda/ordenes/$OID_CODE/asignar")"
CODE="$(sed -n '1p' <<<"$RESP" | awk '{print $2}')"
printf "%s\n" "$(tail -n1 <<<"$RESP")"
[ "$CODE" = "200" ] && echo "✓ Asignación OK (200)" || echo "• Asignación HTTP=$CODE (continuamos)"

echo "▶ GET pendientes"
curl -fsS -H "Authorization: Bearer $TEC_TOKEN" "$TEC_BASE/$TECID/pendientes" >/dev/null && echo "✓ Pendientes OK"

echo "▶ POST iniciar orden $OID_CODE"
RESP="$(curl -s -i -H "Authorization: Bearer $TEC_TOKEN" -X POST "$TEC_BASE/$TECID/ordenes/$OID_CODE/iniciar")"
CODE="$(sed -n '1p' <<<"$RESP" | awk '{print $2}')"
RID="$(awk -F': ' 'tolower($1)=="x-request-id"{print $2}' <<<"$RESP" | tr -d '\r')"
printf "%s\n" "$(tail -n1 <<<"$RESP")"
if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
  echo "✓ Iniciar OK ($CODE)"
else
  echo "✗ No se pudo iniciar (HTTP=$CODE)"; rid_logs "$RID"; exit 1
fi

echo "▶ POST solicitar reagenda (motivo=$MOTIVO_CODE)"
RESP="$(curl -s -i -H "Authorization: Bearer $TEC_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"motivoId\":\"$MOTIVO_ID\",\"observaciones\":\"smoke\"}" \
  -X POST "$TEC_BASE/$TECID/ordenes/$OID_CODE/solicitar-reagenda")"
CODE="$(sed -n '1p' <<<"$RESP" | awk '{print $2}')"
[[ "$CODE" == "200" || "$CODE" == "201" ]] && echo "✓ Reagenda OK ($CODE)" || echo "• Reagenda HTTP=$CODE (continuamos)"

