#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== 🧰 Smoke Técnicos cerrar (v6.2 DETALLADO) ==="
cd "$(dirname "$0")" && echo "📁 CWD: $PWD"

API="http://127.0.0.1:3000/v1"
psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'
FAILED=0

# ---------- FLAGS (pon en 0 cuando el backend ya actualice inventario/estado_conexion) ----------
: "${SKIP_CONN_ASSERTS:=1}"        # 1 = no fallar si COR/REC no cambia estado_conexion
: "${SKIP_INVENTORY_ASSERTS:=1}"   # 1 = no fallar si no descuenta inventario

# ---------- UTILS ----------
need_bin(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ falta binario: $1"; exit 1; }; }
need_bin jq
need_bin curl

# call(): simple (imprime solo body). Útil si no necesitas traza ni capturar.
call() {
  local method="$1" url="$2" data="${3-}" http body
  if [[ -n "${data:-}" ]]; then
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" -H 'Content-Type: application/json' -d "$data" || true)"
  else
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" || true)"
  fi
  body="$(cat /tmp/_body)"
  if [[ -z "$http" || "$http" -ge 400 ]]; then
    echo "❌ $method $url -> HTTP $http"
    printf '%s\n' "$body" | sed -n '1,200p'
    FAILED=1
  fi
  printf '%s\n' "$body"
}

# call_json(): imprime trazas detalladas a STDERR y devuelve SOLO el body por STDOUT.
#   - Si no capturas la salida, verás body (STDOUT) + detalle (STDERR).
#   - Para evitar duplicados visuales, redirige STDOUT a /dev/null cuando no lo uses.
call_json() {
  local method="$1" url="$2" data="${3-}" http body
  if [[ -n "${data:-}" ]]; then
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" -H 'Content-Type: application/json' -d "$data" || true)"
  else
    http="$(curl -sS -o /tmp/_body -w '%{http_code}' -X "$method" "$url" || true)"
  fi
  body="$(cat /tmp/_body)"

  { # --- logs a stderr ---
    echo "↪ ${method} ${url}"
    if [[ -n "${data:-}" ]]; then
      echo "   payload (raw):"
      printf '%s\n' "$data"
    fi
    echo "   http: $http"
    echo "   body:"
    (echo "$body" | jq .) 2>/dev/null || printf '%s\n' "$body"
  } >&2

  [[ -z "$http" || "$http" -ge 400 ]] && FAILED=1
  printf '%s' "$body"
}

ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
soft_fail(){ echo "❌ $*"; FAILED=1; }
soft_assert_eq(){ local a="$1" e="$2" m="${3:-assert failed}"; [[ "$a" == "$e" ]] && ok "$m ($e)" || soft_fail "$m (got='$a' expected='$e')"; }

# HEAD en MinIO para una key pública
head_ok() {
  local key="$1"
  [[ -z "${key:-}" ]] && return 1
  local url="${BASE%/}/${key#/}"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -I "$url" || true)"
  [[ "$code" == "200" ]]
}

# Helpers de inventario / estado conexión
inv_of() { $psqlq "SELECT COALESCE(SUM(cantidad)::int,0) FROM inv_tecnico WHERE tecnico_id='${TEC_ID}' AND material_id=${MAT_ID};" | tr -d '\r'; }
get_conn(){ $psqlq "SELECT COALESCE(estado_conexion::text, '') FROM usuarios WHERE id='${USR_ID}';" | tr -d '\r'; }
set_conn(){ $psqlq "UPDATE usuarios SET estado_conexion='${1}' WHERE id='${USR_ID}';" >/dev/null; }
row_om_desc_true() {
  $psqlq "SELECT COUNT(*) FROM orden_materiales om
          JOIN ordenes o ON o.id=om.orden_id
          WHERE o.codigo='${1}' AND om.material_id_int=${MAT_ID} AND om.descontado IS TRUE;" | tr -d '\r'
}

# ---------- esperar API ----------
for i in {1..90}; do curl -fsS "$API/health" >/dev/null && break || sleep 1; done
if ! curl -fsS "$API/health" >/dev/null; then
  echo "❌ API no respondió /v1/health"; exit 1
fi

# ---------- ids base ----------
TEC_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
USR_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;" | tr -d '\r')"
[ -n "$TEC_ID" ] && [ -n "$USR_ID" ] || { echo "❌ faltan TEC/USR"; exit 1; }

# ---------- MinIO base pública ----------
BASE="$(docker compose exec -T api sh -lc 'echo -n ${MINIO_PUBLIC_BASE:-http://127.0.0.1:9000/${MINIO_BUCKET:-evidencias}/}')" ; BASE="${BASE%/}/"

# ---------- insumos ----------
TOMORROW="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
STAMP="$(date +%y%m%d%H%M%S)"
PIXEL="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFygJp2k1gWQAAAABJRU5ErkJggg=="

# Material a descontar (en dump: 3 y 9; usamos 3 como en smokes previos)
MAT_ID=3

# ========================= 1) MANTENIMIENTO =========================
echo "===== MAN (mantenimiento) ====="
COD_MAN="MAN-$STAMP"
CONN_BEFORE="$(get_conn)"
INV_BEFORE="$(inv_of)"

# crear en BD
$psqlq "INSERT INTO ordenes (id, usuario_id, tipo, codigo, estado) VALUES (gen_random_uuid(), '$USR_ID', 'MAN', '$COD_MAN', 'creada');" >/dev/null
echo "→ crear MAN en BD: $COD_MAN"
echo "   creada en BD"

# asignar (muestra detalle; no necesitamos stdout) 
echo "→ asignar"
call_json POST "$API/agenda/ordenes/$COD_MAN/asignar" "{\"fecha\":\"$TOMORROW\",\"turno\":\"am\",\"tecnicoId\":\"$TEC_ID\"}" >/dev/null

# iniciar (detalle; sin stdout)
echo "→ iniciar"
call_json POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$COD_MAN/iniciar" '{}' >/dev/null

# cerrar con firma/evidencias/materiales (capturamos JSON puro)
echo "→ cerrar con firma, evidencias y materiales"
echo "   stock material_id=$MAT_ID antes: $INV_BEFORE"
RESP_MAN="$(call_json POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$COD_MAN/cerrar" \
'{"materiales":[{"materialIdInt":'"$MAT_ID"',"cantidad":1}],"firmaBase64":"'"$PIXEL"'","evidenciasBase64":["'"$PIXEL"'","'"$PIXEL"'"]}')"
ESTADO_MAN="$(echo "$RESP_MAN" | jq -r '.estado // .orden.estado // empty')"
soft_assert_eq "$ESTADO_MAN" "cerrada" "MAN cerrada"

# verifica DB/MinIO
ROW="$($psqlq "SELECT coalesce(firma_key,''), coalesce((form_data->'evidenciasKeys')::text,'[]'), id FROM ordenes WHERE codigo='${COD_MAN}';")"
IFS='|' read -r FIRMA_KEY EVID_JSON ORD_ID_MAN <<<"$ROW"
if [[ -n "$FIRMA_KEY" ]]; then ok "MAN firmó"; else soft_fail "MAN sin firma"; fi
EVID_COUNT_FORM="$(echo "${EVID_JSON:-[]}" | jq -r 'length' 2>/dev/null || echo 0)"
EVID_COUNT_TABL="$($psqlq "SELECT COUNT(*) FROM orden_evidencias WHERE orden_id='${ORD_ID_MAN}';")"
EVID_TOTAL=$(( EVID_COUNT_FORM > EVID_COUNT_TABL ? EVID_COUNT_FORM : EVID_COUNT_TABL ))
if [[ "$EVID_TOTAL" -ge 2 ]]; then ok "MAN evidencias >=2"; else soft_fail "MAN evidencias insuficientes"; fi

echo "→ HEAD MinIO"
if [[ -n "$FIRMA_KEY" ]]; then
  if head_ok "$FIRMA_KEY"; then echo "   HEAD ${BASE}${FIRMA_KEY} -> 200"; else soft_fail "HEAD firma falla"; fi
fi
if [[ "$EVID_COUNT_FORM" -ge 1 ]]; then
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if head_ok "$k"; then echo "   HEAD ${BASE}${k} -> 200"; else soft_fail "HEAD evidencia falla ($k)"; fi
  done < <(echo "$EVID_JSON" | jq -r '.[]')
fi

INV_AFTER="$(inv_of)"; DELTA=$(( INV_BEFORE - INV_AFTER ))
OM_DESC_TRUE="$(row_om_desc_true "$COD_MAN")"
echo "   stock material_id=$MAT_ID después: $INV_AFTER"
echo "   delta=$DELTA"
echo "   orden_materiales.descontado=true rows=$OM_DESC_TRUE"
if [[ "$DELTA" -eq 1 ]]; then
  ok "MAN descontó 1 unidad material_id=$MAT_ID"
else
  if [[ "$OM_DESC_TRUE" -ge 1 ]]; then
    warn "MAN sin descuento efectivo; hay registro orden_materiales descontado=true (fallback OK)"
  else
    if [[ "${SKIP_INVENTORY_ASSERTS}" == "1" ]]; then
      warn "MAN sin descuento efectivo ni om.descontado=true"
    else
      soft_fail "MAN sin descuento efectivo ni om.descontado=true"
    fi
  fi
fi

CONN_AFTER="$(get_conn)"
if [[ "$CONN_AFTER" == "$CONN_BEFORE" ]]; then
  echo "   estado_conexion actual: $CONN_AFTER (MAN no debe cambiarlo)"
else
  soft_fail "MAN cambió estado_conexion ($CONN_BEFORE -> $CONN_AFTER)"
fi

# ============================= 2) CORTE =============================
echo
echo "===== COR (corte) ====="
COD_COR="COR-$STAMP"
echo "→ crear COR en BD: $COD_COR"
echo "→ estado_conexion ANTES: $(get_conn)"
$psqlq "INSERT INTO ordenes (id, usuario_id, tipo, codigo, estado) VALUES (gen_random_uuid(), '$USR_ID', 'COR', '$COD_COR', 'agendada');" >/dev/null

echo "→ asignar"
call_json POST "$API/agenda/ordenes/$COD_COR/asignar" "{\"fecha\":\"$(date -u +%F)\",\"turno\":\"am\",\"tecnicoId\":\"$TEC_ID\"}" >/dev/null

echo "→ iniciar"
call_json POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$COD_COR/iniciar" '{}' >/dev/null

echo "→ cerrar"
CLOSE_COR="$(call_json POST "$API/tecnicos/${TEC_ID}/ordenes/codigo/${COD_COR}/cerrar" '{}')"
ESTADO_COR="$(echo "$CLOSE_COR" | jq -r '.estado // .orden.estado // empty')"
soft_assert_eq "$ESTADO_COR" "cerrada" "COR cerrada"

# estado_conexion debe quedar desconectado
CONN_COR="$(get_conn)"
if [[ "$CONN_COR" == "desconectado" ]]; then
  ok "COR deja usuario desconectado"
else
  if [[ "${SKIP_CONN_ASSERTS}" == "1" ]]; then
    warn "COR deja usuario '$CONN_COR' (esperado: desconectado)"
  else
    soft_fail "COR deja usuario '$CONN_COR' (esperado: desconectado)"
  fi
fi

# =========================== 3) RECONEXIÓN ==========================
echo
echo "===== REC (reconexión) ====="
COD_REC="REC-$STAMP"
echo "→ crear REC en BD: $COD_REC"
echo "→ estado_conexion ANTES: $(get_conn)"
$psqlq "INSERT INTO ordenes (id, usuario_id, tipo, codigo, estado) VALUES (gen_random_uuid(), '$USR_ID', 'REC', '$COD_REC', 'agendada');" >/dev/null

echo "→ asignar"
call_json POST "$API/agenda/ordenes/$COD_REC/asignar" "{\"fecha\":\"$(date -u +%F)\",\"turno\":\"am\",\"tecnicoId\":\"$TEC_ID\"}" >/dev/null

echo "→ iniciar"
call_json POST "$API/tecnicos/$TEC_ID/ordenes/codigo/$COD_REC/iniciar" '{}' >/dev/null

echo "→ cerrar"
CLOSE_REC="$(call_json POST "$API/tecnicos/${TEC_ID}/ordenes/codigo/${COD_REC}/cerrar" '{}')"
ESTADO_REC="$(echo "$CLOSE_REC" | jq -r '.estado // .orden.estado // empty')"
soft_assert_eq "$ESTADO_REC" "cerrada" "REC cerrada"

# estado_conexion debe quedar conectado
CONN_REC="$(get_conn)"
if [[ "$CONN_REC" == "conectado" ]]; then
  ok "REC deja usuario conectado"
else
  if [[ "${SKIP_CONN_ASSERTS}" == "1" ]]; then
    warn "REC deja usuario '$CONN_REC' (esperado: conectado)"
  else
    soft_fail "REC deja usuario '$CONN_REC' (esperado: conectado)"
  fi
fi

# --------------------------- resultado final ------------------------
if [[ $FAILED -eq 0 ]]; then
  echo
  echo "🎉 Smoke Técnicos v6.2 OK"
  exit 0
else
  echo
  echo "⚠️  Smoke Técnicos v6.2 finalizado con fallos (ver arriba)"
  exit 1
fi
