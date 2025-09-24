#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
TEC_CODE="${TEC_CODE:-TEC-0001}"

say()  { printf '%s\n' "$*"; }
hr()   { printf '%0.s-' {1..80}; echo; }
fail() { say "✗ $*"; exit 1; }

psql_db() {
  docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 "$@"
}

# ---------- helpers HTTP ----------
# POST sin cuerpo (no Content-Type)
http_post_nobody_try() {
  : > /tmp/last.ok; : > /tmp/last.err
  for u in "$@"; do
    code=$(curl -s -o /tmp/.out -w "%{http_code}" -H "$AUTH_TECH" -X POST "$u")
    if [[ "$code" =~ ^2 ]]; then
      cat /tmp/.out > /tmp/last.ok; echo "$u" > /tmp/last.url; return 0
    else
      { echo "---- $u ($code) ----"; cat /tmp/.out; echo; } >> /tmp/last.err
    fi
  done
  return 1
}

# POST con JSON (Content-Type + -d)
http_post_json_try() {
  local data="${1:-{}}"; shift
  : > /tmp/last.ok; : > /tmp/last.err
  for u in "$@"; do
    code=$(curl -s -o /tmp/.out -w "%{http_code}" -H "$AUTH_TECH" -H 'Content-Type: application/json' -X POST "$u" -d "$data")
    if [[ "$code" =~ ^2 ]]; then
      cat /tmp/.out > /tmp/last.ok; echo "$u" > /tmp/last.url; return 0
    else
      { echo "---- $u ($code) ----"; cat /tmp/.out; echo; } >> /tmp/last.err
    fi
  done
  return 1
}

http_get_try() {
  : > /tmp/last.ok; : > /tmp/last.err
  for u in "$@"; do
    code=$(curl -s -o /tmp/.out -w "%{http_code}" -H "$AUTH_TECH" "$u")
    if [[ "$code" =~ ^2 ]]; then
      cat /tmp/.out > /tmp/last.ok; echo "$u" > /tmp/last.url; return 0
    else
      { echo "---- $u ($code) ----"; cat /tmp/.out; echo; } >> /tmp/last.err
    fi
  done
  return 1
}

# ---------- run ----------
say "Health"
curl -fsS "$API_BASE/v1/health" | jq .
hr

# 1) TECID por código
readarray -t TROW <<<"$(psql_db -Atc "select id::text, codigo from tecnicos where codigo='$TEC_CODE' limit 1;")"
[[ ${#TROW[@]} -gt 0 && -n "${TROW[0]}" ]] || fail "No existe técnico con codigo=$TEC_CODE"
IFS='|' read -r TECID TEC_COD_DB <<<"${TROW[0]}"
say "✓ TECID=$TECID (codigo=$TEC_COD_DB)"
hr

# 2) Crear orden efímera y asignarla al técnico
OID_CODE="TEK-$(date +%Y%m%d%H%M%S)"
psql_db <<SQL
insert into ordenes(id, codigo, estado, created_at, updated_at)
values (gen_random_uuid(), '$OID_CODE', 'agendada', now(), now());
update ordenes o
set tecnico_id = t.id
from tecnicos t
where o.codigo = '$OID_CODE' and t.codigo = '$TEC_CODE';
SQL
say "✓ Orden creada y asignada: $OID_CODE"
hr

# 3) JWT TECH — MAYÚSCULAS y tecnicoId explícito
JWT_TECH="$(docker compose exec -T api node -e "
const jwt=require('jsonwebtoken');
console.log(jwt.sign(
  {
    sub:'$TECID',
    tecnicoId:'$TECID',
    code:'$TEC_CODE',
    role:'TECH',
    roles:['TECH'],
    scopes:['tecnicos:read','tecnicos:pendientes','ordenes:read','ordenes:write']
  },
  process.env.JWT_SECRET,
  { expiresIn:'2h' }
));
")"
AUTH_TECH="Authorization: Bearer ${JWT_TECH//$'\n'/}"
say "✓ JWT TECH listo"
hr

# 4) Pendientes — acepta id / código / me
say "Pendientes del técnico"
if http_get_try \
  "$API_BASE/v1/tecnicos/$TECID/pendientes" \
  "$API_BASE/v1/tecnicos/$TEC_CODE/pendientes" \
  "$API_BASE/v1/tecnicos/me/pendientes"
then
  say "✓ pendientes OK"
else
  say "→ detalle pendientes"; cat /tmp/last.err; fail "pendientes 403/404"
fi
hr

# 5) Iniciar: primero SIN body; si falla, reintenta con {}.
say "Iniciar orden $OID_CODE"
if http_post_nobody_try \
  "$API_BASE/v1/tecnicos/$TECID/ordenes/$OID_CODE/iniciar" \
  "$API_BASE/v1/tecnicos/$TEC_CODE/ordenes/$OID_CODE/iniciar" \
  "$API_BASE/v1/tecnicos/me/ordenes/$OID_CODE/iniciar"
then
  say "✓ iniciar OK (sin body) $(cat /tmp/last.url)"
elif http_post_json_try '{}' \
  "$API_BASE/v1/tecnicos/$TECID/ordenes/$OID_CODE/iniciar" \
  "$API_BASE/v1/tecnicos/$TEC_CODE/ordenes/$OID_CODE/iniciar" \
  "$API_BASE/v1/tecnicos/me/ordenes/$OID_CODE/iniciar"
then
  say "✓ iniciar OK (con body) $(cat /tmp/last.url)"
else
  say "→ detalle iniciar"; cat /tmp/last.err; fail "iniciar 4xx"
fi
hr

# 6) Cerrar: misma estrategia (sin body → con {}).
say "Cerrar orden $OID_CODE (sin materiales)"
if http_post_nobody_try \
  "$API_BASE/v1/tecnicos/$TECID/ordenes/$OID_CODE/cerrar" \
  "$API_BASE/v1/tecnicos/$TEC_CODE/ordenes/$OID_CODE/cerrar" \
  "$API_BASE/v1/tecnicos/me/ordenes/$OID_CODE/cerrar"
then
  say "✓ cerrar OK (sin body) $(cat /tmp/last.url)"
elif http_post_json_try '{}' \
  "$API_BASE/v1/tecnicos/$TECID/ordenes/$OID_CODE/cerrar" \
  "$API_BASE/v1/tecnicos/$TEC_CODE/ordenes/$OID_CODE/cerrar" \
  "$API_BASE/v1/tecnicos/me/ordenes/$OID_CODE/cerrar"
then
  say "✓ cerrar OK (con body) $(cat /tmp/last.url)"
else
  say "→ detalle cerrar"; cat /tmp/last.err; fail "cerrar 4xx"
fi

say "✓ smoke_tecnico OK"
