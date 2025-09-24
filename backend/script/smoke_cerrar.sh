set -euo pipefail

# Siempre trabajar desde backend
BASE="/home/yarumo/isp_starter_kit/backend"
[ -d "$BASE" ] || BASE="/root/isp_starter_kit/backend"
cd "$BASE" || { echo "❌ No encuentro $BASE"; exit 1; }
echo "📁 CWD: $(pwd)"

psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

echo "== Rehidratar técnico =="
TECNICO_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
[ -n "${TECNICO_ID:-}" ] || { echo "❌ No hay técnicos"; exit 1; }
echo "TECNICO_ID=$TECNICO_ID"

echo "== Buscar última orden cerrada =="
ORD_ROW="$($psqlq "SELECT id||' '||codigo FROM ordenes WHERE estado='cerrada' ORDER BY cerrada_at DESC LIMIT 1;" | tr -d '\r' || true)"
if [ -n "${ORD_ROW:-}" ]; then
  ORD_ID="$(echo "$ORD_ROW" | awk '{print $1}')"
  ORD_COD="$(echo "$ORD_ROW" | awk '{print $2}')"
  echo "Usando última cerrada: ORD_ID=$ORD_ID  ORD_COD=$ORD_COD"
else
  echo "No hay cerradas; crearé una nueva y la cerraré…"
  # Usuario (NULL si no hay)
  USUARIO_ID="$($psqlq "SELECT COALESCE((SELECT usuario_id FROM ordenes WHERE usuario_id IS NOT NULL LIMIT 1),
                                        (SELECT id FROM usuarios LIMIT 1));" | tr -d '\r' || true)"
  [ -n "${USUARIO_ID:-}" ] && USUARIO_SQL="'$USUARIO_ID'" || USUARIO_SQL="NULL"
  # Insert
  ORD_ID="$(
    docker compose exec -T db sh -lc "cat <<'SQL' | psql -qAtX -U ispuser -d ispdb
INSERT INTO ordenes (id,codigo,estado,tecnico_id,tipo,subtotal,total,usuario_id)
VALUES (uuid_generate_v4(), 'INS-'||extract(epoch from now())::bigint,
        'agendada', '${TECNICO_ID}', 'INS', 0, 0, ${USUARIO_SQL})
RETURNING id;
SQL
" | tr -d '\r' | head -n1
  )"
  echo "$ORD_ID" | grep -Eq '^[0-9a-f-]{36}$' || { echo "❌ ORD_ID inválido: '$ORD_ID'"; exit 1; }
  ORD_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_ID}' LIMIT 1;" | tr -d '\r')"
  echo "Nueva orden: ORD_ID=$ORD_ID  ORD_COD=$ORD_COD"

  # Iniciar
  curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/iniciar" \
    -H "Content-Type: application/json" | jq

  # Material (si hay stock)
  MAT_ID="$($psqlq "SELECT material_id FROM inv_tecnico WHERE tecnico_id='${TECNICO_ID}' AND cantidad>0 LIMIT 1;" | tr -d '\r' || true)"
  if [ -n "${MAT_ID:-}" ]; then
    BODY="$(jq -nc --arg t "$TECNICO_ID" --argjson m "$MAT_ID" '{tecnicoId:$t,materiales:[{materialIdInt:$m,cantidad:1}]}' )"
  else
    BODY="$(jq -nc --arg t "$TECNICO_ID" '{tecnicoId:$t}')"
  fi

  # Cerrar (1ra vez: debe quedar cerrada y crear PDF)
  curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/cerrar" \
    -H "Content-Type: application/json" -d "$BODY" | jq
fi

echo "== Idempotencia: cerrar de nuevo =="
curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/cerrar" \
  -H "Content-Type: application/json" \
  -d "{\"tecnicoId\":\"$TECNICO_ID\"}" | jq

echo "== DB tras idempotencia =="
$psqlq "SELECT codigo, estado, pdf_key, pdf_url FROM ordenes WHERE id='${ORD_ID}';"

echo "== Saneo: borrar objeto y rehacerlo =="
docker compose exec -T minio sh -lc '
mc alias set local http://localhost:9000 minioadmin minioadmin >/dev/null 2>&1
mc rm --force local/evidencias/ordenes/'"$ORD_COD"'.pdf || true
mc stat local/evidencias/ordenes/'"$ORD_COD"'.pdf >/dev/null 2>&1 && echo "Aún existe" || echo "Eliminado"
'

echo "== Cerrar otra vez para re-crear PDF =="
curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/cerrar" \
  -H "Content-Type: application/json" \
  -d "{\"tecnicoId\":\"$TECNICO_ID\"}" | jq

echo "== Verificar objeto en MinIO =="
docker compose exec -T minio sh -lc '
mc alias set local http://localhost:9000 minioadmin minioadmin >/dev/null 2>&1
mc stat local/evidencias/ordenes/'"$ORD_COD"'.pdf && echo "OK: existe"
'

echo "== HEAD al PDF =="
curl -sSI "http://127.0.0.1:9000/evidencias/ordenes/${ORD_COD}.pdf" | sed -n '1,12p'
