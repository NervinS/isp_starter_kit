#!/usr/bin/env bash
# Smoke Técnico (pendientes → iniciar → cerrar)
# Requiere: curl, jq, docker compose (si quieres tocar DB o generar JWT dentro del contenedor)
set -euo pipefail

# ========================
# Config
# ========================
API_BASE="${API_BASE:-http://127.0.0.1:3000}"
# Puedes sobreescribir TEC_ID por env o por arg1
TEC_ID="${TEC_ID:-${1:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}}"

# ========================
# Helpers
# ========================
say() { echo -e "▶ $*" >&2; }
ok()  { echo -e "✓ $*" >&2; }
die() { echo -e "✗ $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Falta comando '$1' en PATH."; }
need_jq()  { need_cmd jq; }
need_curl(){ need_cmd curl; }

dc_ok() {
  command -v docker >/dev/null 2>&1 || return 1
  command -v docker-compose >/dev/null 2>&1 && return 0
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && return 0
  return 1
}

dc() {
  # Normaliza docker compose
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    docker compose "$@"
  fi
}

curl_json() {
  # Envoltorio para curl que siempre imprime cuerpo (stdout)
  # Uso: curl_json -H "Header: v" URL
  curl --show-error -s "$@"
}

uuid_now() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen; else cat /proc/sys/kernel/random/uuid; fi
}

# ========================
# Tokens
# ========================
maybe_mint_tokens() {
  if [[ -n "${AUTH_ADMIN:-}" && -n "${AUTH_TEC:-}" ]]; then
    return 0
  fi

  dc_ok || die "Necesito 'docker compose' para mintear JWT dentro del contenedor api, o exporta AUTH_ADMIN / AUTH_TEC tú mismo."

  say "Generando JWT ADMIN (docker compose exec api …)"
  local tadmin
  tadmin="$(dc exec -T api node -e "const jwt=require('jsonwebtoken');console.log(jwt.sign({sub:'ADMIN-USER',role:'admin'}, process.env.JWT_SECRET,{expiresIn:'8h'}))")"
  AUTH_ADMIN="Authorization: Bearer ${tadmin}"

  say "Generando JWT TECH para TEC_ID=${TEC_ID}"
  local ttec
  ttec="$(dc exec -T api node -e "const jwt=require('jsonwebtoken');const TEC_ID='${TEC_ID}';console.log(jwt.sign({sub:TEC_ID,role:'TECH',tecId:TEC_ID}, process.env.JWT_SECRET,{expiresIn:'8h'}))")"
  AUTH_TEC="Authorization: Bearer ${ttec}"
}

# ========================
# Material
# ========================
ensure_material() {
  need_jq
  say "Buscando materiales vía API…"
  local res count mid
  res="$(curl_json -H "$AUTH_ADMIN" "$API_BASE/v1/materiales" || true)"
  count="$(echo "${res:-[]}" | jq 'length' 2>/dev/null || echo 0)"
  if [[ "$count" -gt 0 ]]; then
    mid="$(echo "$res" | jq -r '.[0].id')"
    printf "%s" "$mid"
    return 0
  fi

  if dc_ok; then
    say "No hay materiales por API; insertando base en DB (MAT-0001)…"
    dc exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "
      INSERT INTO materiales (codigo,nombre,precio,tipo,es_serial)
      VALUES ('MAT-0001','Conector RJ45',1200,'CONSUMIBLE',false)
      ON CONFLICT (codigo) DO NOTHING;
    " >/dev/null
    res="$(curl_json -H "$AUTH_ADMIN" "$API_BASE/v1/materiales")"
    count="$(echo "$res" | jq 'length')"
    if [[ "$count" -eq 0 ]]; then
      die "No pude obtener material por API después de insertar."
    fi
    mid="$(echo "$res" | jq -r '.[0].id')"
    printf "%s" "$mid"
    return 0
  fi

  die "Sin materiales y sin acceso a DB para crearlo."
}

# ========================
# Orden helpers
# ========================
create_clean_order() {
  # Crea una orden "creada" por DB (si hay compose); si no, igual genera el código para que se asigne vía API
  local cod="MAN-$(date +%Y%m%d%H%M%S)"
  if dc_ok; then
    say "Creando orden ${cod} en DB…"
    dc exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "
      DELETE FROM ordenes WHERE codigo='${cod}';
      INSERT INTO ordenes (codigo,tipo,estado,agendado_para,turno)
      VALUES ('${cod}','MAN','creada', current_date, 'am');
    " >/dev/null
    ok "Orden ${cod} creada."
  else
    say "Sin DB local; usaré código ${cod} y la moveré de estado por API."
  fi
  printf "%s" "$cod"
}

assign_order_to_tech() {
  local cod="$1"
  say "Asignando ${cod} → técnico ${TEC_ID}…"
  local payload res okflag
  payload="$(jq -nc --arg tec "$TEC_ID" --arg fecha "$(date +%F)" --arg turno "am" \
    '{tecnicoId:$tec,fecha:$fecha,turno:$turno}')"
  res="$(curl_json -X POST "$API_BASE/v1/agenda/ordenes/$cod/asignar" -H "$AUTH_ADMIN" -H 'Content-Type: application/json' -d "$payload" || true)"
  okflag="$(echo "$res" | jq -r '.ok // false' 2>/dev/null || echo false)"
  [[ "$okflag" == "true" ]] || { echo "$res" | jq . || echo "$res"; die "Falló asignación por API."; }
  ok "Asignación OK."
}

# ========================
# MAIN
# ========================
need_curl
maybe_mint_tokens

say "Smoke Técnico (pendientes → iniciar → cerrar) - API=${API_BASE}"

MAT_ID="$(ensure_material)"
ok "Material OK (id=${MAT_ID})"

COD="$(create_clean_order)"
assign_order_to_tech "$COD"

say "Consultando pendientes…"
PEND="$(curl_json -H "$AUTH_TEC" "$API_BASE/v1/tecnicos/$TEC_ID/pendientes" || true)"
echo "$PEND" | jq -e --arg c "$COD" '.ok==true and (.items|map(.codigo)|index($c) != null)' >/dev/null 2>&1 \
  || { echo "$PEND" | jq . || echo "$PEND"; die "Pendientes no incluye la orden ${COD}."; }
ok "Pendientes OK (incluye ${COD})."

# Asegura estado 'agendada' por si se ensució
if dc_ok; then
  say "Normalizando estado a 'agendada' en DB (por si acaso)…"
  dc exec -T db psql -U ispuser -d ispdb -c \
    "UPDATE ordenes SET estado='agendada', iniciada_at=NULL, cerrada_at=NULL WHERE codigo='${COD}';" >/dev/null
fi

# Iniciar
say "Iniciando orden ${COD}…"
RESP_START="$(curl_json -X POST "$API_BASE/v1/tecnicos/$TEC_ID/ordenes/$COD/iniciar" -H "$AUTH_TEC" || true)"
echo "$RESP_START" | jq -e '.ok==true and .estado=="iniciada"' >/dev/null 2>&1 \
  || { echo "$RESP_START" | jq . || echo "$RESP_START"; die "Fallo iniciar."; }
ok "Iniciar OK."

# Confirma estado si hay DB
if dc_ok; then
  say "Confirmando estado en DB…"
  dc exec -T db psql -U ispuser -d ispdb -c \
    "SELECT codigo, estado FROM ordenes WHERE codigo='${COD}';" | sed -n '3,4p' >&2
fi

# Cerrar con consumo (1 unidad)
say "Cerrando orden ${COD} con material id=${MAT_ID} x1…"
RESP_CLOSE="$(curl --show-error -sS -X POST "$API_BASE/v1/tecnicos/$TEC_ID/ordenes/$COD/cerrar" \
  -H "$AUTH_TEC" -H 'Content-Type: application/json' \
  -d "{\"materiales\":[{\"materialId\":$MAT_ID,\"cantidad\":1,\"precioUnitario\":1200}],\"snapshot\":{\"nota\":\"smoke tecnico\"}}")" || {
    echo "$RESP_CLOSE" >&2
    die "Cerrar devolvió error (nivel curl)."
  }

echo "$RESP_CLOSE" | jq -e '.ok==true and .estado=="cerrada"' >/dev/null 2>&1 \
  || { echo "$RESP_CLOSE" | jq . || echo "$RESP_CLOSE"; die "Cerrar no respondió ok=true/estado=cerrada."; }
ok "Cerrar OK."

# Mostrar totales si hay DB
if dc_ok; then
  say "Verificando totales en DB…"
  dc exec -T db psql -U ispuser -d ispdb -c "
    SELECT codigo, estado, iniciada_at, cerrada_at, subtotal, total
      FROM ordenes
     WHERE codigo='${COD}';
    SELECT material_id, cantidad, precio_unitario, total_calculado
      FROM orden_materiales om
      JOIN ordenes o ON o.id = om.orden_id
     WHERE o.codigo='${COD}';
  " | sed -n '3,999p'
fi

ok "Smoke Técnico OK (orden=${COD})."
