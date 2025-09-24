#!/usr/bin/env bash
set -euo pipefail

echo "=== 🚦 Smoke Agenda ==="
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CWD"
echo "📁 CWD: $PWD"

# Helpers
API_BASE="http://127.0.0.1:3000/v1"
psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

# Función: abortar con mensaje
die(){ echo "❌ $*" >&2; exit 1; }

# Función: imprimir título
step(){ echo -e "\n== $* =="; }

# Función: curl + jq (falla si statusCode >= 400)
req_json(){
  local METHOD="$1"; shift
  local URL="$1"; shift
  local DATA="${1-}"; shift || true
  if [[ -n "$DATA" ]]; then
    RESP="$(curl -s -X "$METHOD" "$URL" -H 'Content-Type: application/json' -d "$DATA")"
  else
    RESP="$(curl -s -X "$METHOD" "$URL")"
  fi
  # Si API regresó error estándar Nest
  if echo "$RESP" | jq -e '.statusCode? // empty' >/dev/null; then
    echo "$RESP" | jq .
    die "Respuesta con error de la API: $(echo "$RESP" | jq -r '.message // "Unknown error"')"
  fi
  echo "$RESP"
}

# 0) Catálogo de motivos para reagenda
step "0) GET /catalogos/motivos-reagenda"
CATALOGO="$(req_json GET "$API_BASE/catalogos/motivos-reagenda")"
echo "$CATALOGO" | jq '{ok, count:(.items|length)}'
COUNT="$(echo "$CATALOGO" | jq -r '.items | length')"
[[ "$COUNT" -ge 1 ]] || die "Catálogo de motivos vacío"

# Elegimos el primer código si existe 'cliente-ausente', preferir ese
MOTIVO="cliente-ausente"
if ! echo "$CATALOGO" | jq -r '.items[].codigo' | grep -qx "$MOTIVO"; then
  MOTIVO="$(echo "$CATALOGO" | jq -r '.items[0].codigo')"
fi
echo "🎯 motivo elegido: $MOTIVO"

# Rehidratar técnico/usuario
TECNICO_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;")"
USUARIO_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;")"
[[ -n "$TECNICO_ID" && -n "$USUARIO_ID" ]] || die "No hay TECNICO_ID/USUARIO_ID en DB"

# 1) Crear orden en estado 'agendada' con DEFAULT codigo
step "1) Crear orden"
ORD_ID="$(docker compose exec -T db sh -lc "psql -qAtX -U ispuser -d ispdb -c \"
  INSERT INTO ordenes (id,codigo,estado,tecnico_id,tipo,subtotal,total,usuario_id)
  VALUES (uuid_generate_v4(), DEFAULT, 'agendada', '${TECNICO_ID}', 'INS', 0, 0, '${USUARIO_ID}')
  RETURNING id;\"")"
ORD_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_ID}';")"
[[ -n "$ORD_COD" ]] || die "No se obtuvo código de orden"
echo "🆕 orden: $ORD_COD"

# Fechas
TOMORROW="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
DAY2="$(date -u -d '+2 day' +%F 2>/dev/null || date -u -v+2d +%F)"

# 2) Asignar (fecha/turno/técnico)
step "2) POST /agenda/ordenes/:codigo/asignar"
ASIGNAR_PAYLOAD="$(jq -nc --arg f "$TOMORROW" --arg t "am" --arg tech "$TECNICO_ID" '{fecha:$f, turno:$t, tecnicoId:$tech}')"
RESP_ASIGNAR="$(req_json POST "$API_BASE/agenda/ordenes/${ORD_COD}/asignar" "$ASIGNAR_PAYLOAD")"
echo "$RESP_ASIGNAR" | jq .
# Validaciones mínimas payload
test "$(echo "$RESP_ASIGNAR" | jq -r '.ok')" = "true" || die "Asignar no respondió ok=true"
test "$(echo "$RESP_ASIGNAR" | jq -r '.orden[0].agendadoPara')" = "$TOMORROW" || die "Asignar no fijó agendadoPara esperado"
test "$(echo "$RESP_ASIGNAR" | jq -r '.orden[0].turno')" = "am" || die "Asignar no fijó turno=am"

# 3) Reagendar con motivo (texto + código) y persistencia real
step "3) POST /agenda/ordenes/:codigo/reagendar (con motivo)"
REAGENDAR_PAYLOAD="$(jq -nc --arg f "$DAY2" --arg t "pm" --arg mc "$MOTIVO" --arg m "Cliente reprograma" '{fecha:$f, turno:$t, motivoCodigo:$mc, motivo:$m}')"
RESP_REAGENDAR="$(req_json POST "$API_BASE/agenda/ordenes/${ORD_COD}/reagendar" "$REAGENDAR_PAYLOAD")"
echo "$RESP_REAGENDAR" | jq .
test "$(echo "$RESP_REAGENDAR" | jq -r '.ok')" = "true" || die "Reagendar no respondió ok=true"
test "$(echo "$RESP_REAGENDAR" | jq -r '.orden[0].agendadoPara')" = "$DAY2" || die "Reagendar no fijó nueva fecha"
test "$(echo "$RESP_REAGENDAR" | jq -r '.orden[0].turno')" = "pm" || die "Reagendar no fijó turno=pm"
test "$(echo "$RESP_REAGENDAR" | jq -r '.orden[0].motivo')" != "null" || die "Payload de reagendar no trajo 'motivo'"
test "$(echo "$RESP_REAGENDAR" | jq -r '.orden[0].motivoCodigo')" != "null" || die "Payload de reagendar no trajo 'motivoCodigo'"

step "3b) Validación en DB (persistencia real)"
DB_ROW="$($psqlq "SELECT to_char(agendado_para,'YYYY-MM-DD')
                        , turno
                        , motivo_reagenda
                        , motivo_reagenda_codigo
                   FROM ordenes
                   WHERE codigo='${ORD_COD}';")"
echo "$DB_ROW"
DB_DATE="$(echo "$DB_ROW" | cut -d'|' -f1)"
DB_TURNO="$(echo "$DB_ROW" | cut -d'|' -f2)"
DB_MOTIVO="$(echo "$DB_ROW" | cut -d'|' -f3)"
DB_MOTIVO_COD="$(echo "$DB_ROW" | cut -d'|' -f4)"

[[ "$DB_DATE" = "$DAY2" ]] || die "DB.agendado_para no coincide ($DB_DATE != $DAY2)"
[[ "$DB_TURNO" = "pm" ]] || die "DB.turno no es pm ($DB_TURNO)"
[[ -n "$DB_MOTIVO" ]] || die "DB.motivo_reagenda vacío"
[[ -n "$DB_MOTIVO_COD" ]] || die "DB.motivo_reagenda_codigo vacío"

# 4) Cancelar: no debe tocar motivos de REAGENDA
step "4) POST /agenda/ordenes/:codigo/cancelar"
RESP_CANCELAR="$(req_json POST "$API_BASE/agenda/ordenes/${ORD_COD}/cancelar")"
echo "$RESP_CANCELAR" | jq .
test "$(echo "$RESP_CANCELAR" | jq -r '.ok')" = "true" || die "Cancelar no respondió ok=true"
test "$(echo "$RESP_CANCELAR" | jq -r '.orden[0].agendadoPara')" = "null" || die "Cancelar no limpió agendadoPara"
test "$(echo "$RESP_CANCELAR" | jq -r '.orden[0].turno')" = "null" || die "Cancelar no limpió turno"

step "4b) DB tras cancelar (motivos de reagenda intactos)"
DB_ROW2="$($psqlq "SELECT motivo_reagenda, motivo_reagenda_codigo FROM ordenes WHERE codigo='${ORD_COD}';")"
echo "$DB_ROW2"
[[ "$(echo "$DB_ROW2" | cut -d'|' -f1)" = "$DB_MOTIVO" ]] || die "motivo_reagenda cambió tras cancelar"
[[ "$(echo "$DB_ROW2" | cut -d'|' -f2)" = "$DB_MOTIVO_COD" ]] || die "motivo_reagenda_codigo cambió tras cancelar"

# 5) Anular: flujo independiente que no debe tocar los motivos de REAGENDA
step "5) POST /agenda/ordenes/:codigo/anular"
ANULAR_PAYLOAD="$(jq -nc --arg m "Cliente desistió" --arg mc "$MOTIVO" '{motivo:$m, motivoCodigo:$mc}')"
RESP_ANULAR="$(req_json POST "$API_BASE/agenda/ordenes/${ORD_COD}/anular" "$ANULAR_PAYLOAD")"
echo "$RESP_ANULAR" | jq .
test "$(echo "$RESP_ANULAR" | jq -r '.ok')" = "true" || die "Anular no respondió ok=true"
test "$(echo "$RESP_ANULAR" | jq -r '.orden[0].estado')" = "cancelada" || die "Anular no dejó estado=cancelada"

echo -e "\n✅ Smoke Agenda OK: asignar ✔, reagendar (con motivo persistido) ✔, cancelar ✔, anular ✔."
