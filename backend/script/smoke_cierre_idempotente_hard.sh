#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# Config
# -------------------------
API="${API_BASE:-http://127.0.0.1:3000}"
TEC_ID="${TEC_ID:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"
HDR_CT="Content-Type: application/json"

# Si quieres forzar un material válido, exporta MAT_ID=123 (número)
MAT_ID="${MAT_ID:-}"

# -------------------------
# Helpers
# -------------------------
die() { echo "✗ $*" >&2; exit 1; }

http_code() {
  curl -s -o /dev/null -w "%{http_code}" "$@"
}

curl_show_headers() {
  # imprime solo headers (útil para extraer X-Request-Id)
  curl -s -D - -o /dev/null "$@"
}

extract_request_id() {
  # lee X-Request-Id del STDIN (headers HTTP)
  awk 'BEGIN{IGNORECASE=1} /^X-Request-Id:/ {gsub("\r",""); print $2 }'
}

log_block_by_request_id() {
  local rid="$1"
  docker compose logs api --since=10m | awk -v r="$rid" '$0 ~ r {blk=40} blk>0 {print; blk--}'
}

# -------------------------
# 0) Obtener variantes de token
# -------------------------
eval "$(./script/jwt_tecnico_variants.sh "$TEC_ID")"

# Conjunto de candidatos (Bearer + los 6 tokens generados)
CAND=( "$SUB" "$TECID" "$BOTH" "$SUB_PLUS" "$TECID_PLUS" "$BOTH_PLUS" )

# -------------------------
# 1) Asegurar orden creada y agendada
# -------------------------
ORD="${ORD_CODIGO:-MAN-TEST-$(date +%Y%m%d%H%M%S)}"

# Inserta la orden si no existe
docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "
INSERT INTO ordenes (id, codigo, estado, creado_at, actualizado_at)
VALUES (gen_random_uuid(), '$ORD', 'creada', now(), now())
ON CONFLICT (codigo) DO NOTHING;" >/dev/null

# Usa un token “cualquiera” para agenda (los endpoints públicos tuyos ya funcionaban)
TOKEN_TMP="Bearer ${CAND[0]}"
curl -sfS -X POST "$API/v1/agenda/ordenes/$ORD/asignar" \
  -H "Authorization: $TOKEN_TMP" -H "$HDR_CT" \
  -d "{\"tecnicoId\":\"$TEC_ID\",\"fecha\":\"$(date -I)\",\"turno\":\"am\"}" >/dev/null

# -------------------------
# 2) Encontrar un token que de 2xx/409 en /iniciar
#    (ANTES aceptaba 500 por error — corregido)
# -------------------------
TOKEN_OK=""
for raw in "${CAND[@]}"; do
  T="Bearer $raw"
  code=$(http_code -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$ORD/iniciar" -H "Authorization: $T")
  if [[ "$code" =~ ^2..$ || "$code" == "409" ]]; then
    TOKEN_OK="$T"
    echo "✔ Token compatible para /iniciar (HTTP $code)."
    break
  else
    echo "… variante respondió $code, intentando siguiente."
  fi
done

if [ -z "$TOKEN_OK" ]; then
  echo "✗ No se encontró un token compatible para /iniciar (necesitamos 2xx/409)."
  echo "Sugerencias:"
  echo "  - El guard puede requerir otro claim (p.ej. 'user.rol', 'claims.tecnicoId')."
  echo "  - Decodifica cualquier token y te digo qué ajustar:"
  echo "      printf '%s' \"$BOTH_PLUS\" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq ."
  exit 1
fi

# Asegurar que /iniciar quedó OK (idempotente: tolera 409/2xx)
http_code -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$ORD/iniciar" -H "Authorization: $TOKEN_OK" >/dev/null

# -------------------------
# 3) Cierre idempotente (dos veces con misma Idempotency-Key)
# -------------------------
IDK="$(uuidgen)"

if [[ -n "$MAT_ID" && "$MAT_ID" =~ ^[0-9]+$ ]]; then
  # modo con material válido (numérico)
  payload=$(jq -n --argjson mid "$MAT_ID" \
    '{observaciones:"cierre smoke", fotos:["minio://evidencias/1.jpg"], firmaKey:"minio://firmas/demo.png",
      materiales:[{materialId:$mid, cantidad:1}] }')
else
  # modo “duro”: incluye materialId NO numérico para probar tolerancia del servicio
  payload='{"observaciones":"cierre smoke","fotos":["minio://evidencias/1.jpg"],"firmaKey":"minio://firmas/demo.png","materiales":[{"materialId":"DROP_1","cantidad":1}]}'
fi

echo "== 1ª llamada /cerrar (esperado 200) =="
# guardamos headers para extraer X-Request-Id
HDRS_1="$(curl_show_headers -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$ORD/cerrar" \
  -H "Authorization: $TOKEN_OK" -H "$HDR_CT" -H "Idempotency-Key: $IDK" \
  --data "$payload")"
CODE1=$(printf "%s" "$HDRS_1" | awk 'NR==1 {print $2}')
RID1=$(printf "%s" "$HDRS_1" | extract_request_id || true)
echo "$HDRS_1" | sed -n '1,20p'
echo

if [[ ! "$CODE1" =~ ^2..$ && "$CODE1" != "409" ]]; then
  echo "✗ /cerrar 1a respuesta no exitosa (HTTP $CODE1)."
  if [ -n "${RID1:-}" ]; then
    echo "--- Logs por Request-Id: $RID1 ---"
    log_block_by_request_id "$RID1" || true
  fi
  exit 1
fi

echo "== 2ª llamada /cerrar con misma Idempotency-Key (esperado 200/204/409) =="
HDRS_2="$(curl_show_headers -X POST "$API/v1/tecnicos/$TEC_ID/ordenes/$ORD/cerrar" \
  -H "Authorization: $TOKEN_OK" -H "$HDR_CT" -H "Idempotency-Key: $IDK" \
  --data "$payload")"
CODE2=$(printf "%s" "$HDRS_2" | awk 'NR==1 {print $2}')
RID2=$(printf "%s" "$HDRS_2" | extract_request_id || true)
echo "$HDRS_2" | sed -n '1,20p'
echo

if [[ ! "$CODE2" =~ ^2..$ && "$CODE2" != "204" && "$CODE2" != "409" ]]; then
  echo "✗ /cerrar 2a respuesta no idempotente (HTTP $CODE2)."
  if [ -n "${RID2:-}" ]; then
    echo "--- Logs por Request-Id: $RID2 ---"
    log_block_by_request_id "$RID2" || true
  fi
  exit 1
fi

echo "✓ smoke_cierre_idempotente_hard OK"
