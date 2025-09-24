#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# smoke-tecnicos.sh
#   - Espera a que la API esté viva (/v1/health o /health)
#   - Confirma el bypass dentro del contenedor
#   - Obtiene pendientes del técnico demo
#   - Elige una OID no-cerrada
#   - Inicia la OID
#   - Cierra la OID con Idempotency-Key y repite para probar idempotencia
# Requisitos:
#   - docker compose funcionando
#   - La API mapeando el puerto 3000 (o descubrible con `docker compose port`)
#   - La imagen del contenedor tiene Node (la oficial de Node ya lo trae)
# ============================================================

TEC_ID="${TEC_ID:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"
AUTH_HEADER="${AUTH_HEADER:-Authorization: Bearer dummy}"

# ---------- util ----------
say() { printf '%s\n' "$*"; }
hr()  { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '='; }

# ---------- espera API (host o dentro del contenedor) ----------
wait_api() {
  say "Esperando API..."

  # 1) Descubrir BASE si no viene por env
  if [ -z "${API_BASE:-}" ]; then
    if PORTLINE="$(docker compose port api 3000 2>/dev/null)" && [ -n "$PORTLINE" ]; then
      HOST_PORT="${PORTLINE##*:}"
      API="http://127.0.0.1:${HOST_PORT}"
    else
      API="http://127.0.0.1:3000"
    fi
  else
    API="$API_BASE"
  fi
  export API

  # helpers
  host_httpcode () {
    local url="$1"
    curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true
  }
  inctr_httpcode () {
    local path="$1"
    docker compose exec -T api node -e "
const http=require('http');
http.get('http://127.0.0.1:3000$path',res=>{process.stdout.write(String(res.statusCode||0));})
  .on('error',()=>process.stdout.write('0'));
" 2>/dev/null || true
  }

  # 2) Intentar hasta 120s contra /v1/health y /health
  for _ in $(seq 1 120); do
    for PATHX in /v1/health /health; do
      CODE_HOST="$(host_httpcode "$API$PATHX")"
      [ "$CODE_HOST" = "200" ] && { say "API healthy (host) -> $API$PATHX"; return 0; }

      CODE_CTR="$(inctr_httpcode "$PATHX")"
      [ "$CODE_CTR" = "200" ] && { say "API healthy (in-container) -> http://127.0.0.1:3000$PATHX"; return 0; }
    done
    sleep 1
  done

  say "ERROR: API no respondió 200 en /v1/health ni /health (host/cont) en 120s."
  say "Sugerencias:"
  say "  - Logs:  docker compose logs -f api"
  say "  - Puerto: docker compose port api 3000"
  exit 1
}

# ---------- helpers que usan Node *dentro* del contenedor ----------
print_smoke_env() {
  docker compose exec -T api node -e "console.log('SMOKE_BYPASS_TECH_GUARD=',process.env.SMOKE_BYPASS_TECH_GUARD||'');"
}

pick_material_id() {
  docker compose exec -T api node -e "
const http=require('http');
http.get('http://127.0.0.1:3000/v1/materiales',res=>{
  let d='';res.on('data',c=>d+=c);res.on('end',()=>{
    try{
      const j=JSON.parse(d);
      const items=(j.items||j||[]);
      const first=items.find(m=>{
        const id = (m && (m.id ?? m.materialId));
        return Number.isInteger(id) || (typeof id==='string' && /^\d+$/.test(id));
      });
      const id=first ? (first.id ?? first.materialId) : 1;
      process.stdout.write(String(id));
    }catch{ process.stdout.write('1'); }
  });
}).on('error',()=>process.stdout.write('1'));
"
}

pick_oid() {
  # Elige la primera orden cuyo estado != 'cerrada'
  docker compose exec -T api node -e "
const http=require('http');
http.get('http://127.0.0.1:3000/v1/agenda/ordenes',res=>{
  let d='';res.on('data',c=>d+=c);res.on('end',()=>{
    try{
      const j=JSON.parse(d);
      const items=(j.items||j||[]);
      const prefer=['agendada','en_proceso','iniciada','creada'];
      for(const pref of prefer){
        const it=items.find(x=>x && x.codigo && x.estado===pref);
        if(it){ process.stdout.write(it.codigo); return; }
      }
      const it=items.find(x=>x && x.codigo && x.estado!=='cerrada');
      process.stdout.write(it?it.codigo:'');
    }catch{ process.stdout.write(''); }
  });
}).on('error',()=>process.stdout.write(''));
"
}

# ---------- requests legibles ----------
do_get_pendientes() {
  hr
  say "== GET pendientes"
  curl -i "${API}/v1/tecnicos/${TEC_ID}/pendientes" -H "$AUTH_HEADER"
}

do_post_iniciar() {
  local OID="$1"
  hr
  say "== POST iniciar  (OID: $OID)"
  curl -i -X POST "${API}/v1/tecnicos/${TEC_ID}/ordenes/${OID}/iniciar" \
    -H "$AUTH_HEADER"
}

do_post_cerrar_twice() {
  local OID="$1" MAT_ID="$2"
  local IDK
  IDK="$(uuidgen || cat /proc/sys/kernel/random/uuid || echo "SMK-$(date +%s)")"

  hr
  say "== POST cerrar #1  (Idempotency-Key: $IDK, materialId=$MAT_ID)"
  curl -i -X POST "${API}/v1/tecnicos/${TEC_ID}/ordenes/${OID}/cerrar" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: ${IDK}" \
    -d "{\"observaciones\":\"smoke\",\"materiales\":[{\"materialId\":${MAT_ID},\"cantidad\":1}],\"fotos\":[],\"firmaKey\":\"minio://firmas/demo.png\"}"

  hr
  say "== POST cerrar #2  (misma Idempotency-Key)"
  curl -i -X POST "${API}/v1/tecnicos/${TEC_ID}/ordenes/${OID}/cerrar" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: ${IDK}" \
    -d "{\"observaciones\":\"smoke\",\"materiales\":[{\"materialId\":${MAT_ID},\"cantidad\":1}],\"fotos\":[],\"firmaKey\":\"minio://firmas/demo.png\"}"
}

# ============================================================
# MAIN
# ============================================================
wait_api
hr
say "SMOKE_BYPASS_TECH_GUARD dentro del contenedor:"
print_smoke_env

do_get_pendientes

say
say "Buscando OID válido..."
OID="$(pick_oid || true)"
if [ -z "$OID" ]; then
  say "No pude elegir OID automáticamente. Intentá crear/asignar una y reintenta." >&2
  exit 2
fi
say "OID elegido: $OID"

do_post_iniciar "$OID"

# materialId numérico para evitar errores de tipo
MAT_ID="$(pick_material_id || echo 1)"
[ -z "$MAT_ID" ] && MAT_ID=1
say "Usando materialId=${MAT_ID}"

do_post_cerrar_twice "$OID" "$MAT_ID"

hr
say "SMOKE listo."
