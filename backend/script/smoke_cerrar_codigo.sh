#!/usr/bin/env bash
set -euo pipefail
BASE="/home/yarumo/isp_starter_kit/backend"; [ -d "$BASE" ] || BASE="/root/isp_starter_kit/backend"
cd "$BASE"
psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

echo "📁 CWD: $(pwd)"
TECNICO_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
[ -n "${TECNICO_ID:-}" ] || { echo "❌ No hay técnicos"; exit 1; }

ORD_COD="$($psqlq "SELECT codigo FROM ordenes WHERE estado='cerrada' ORDER BY cerrada_at DESC LIMIT 1;" | tr -d '\r' || true)"
if [ -z "${ORD_COD:-}" ]; then
  echo "No hay cerradas; creo una nueva"
  USUARIO_ID="$($psqlq "SELECT COALESCE((SELECT usuario_id FROM ordenes WHERE usuario_id IS NOT NULL LIMIT 1),
                                        (SELECT id FROM usuarios LIMIT 1));" | tr -d '\r' || true)"
  [ -n "${USUARIO_ID:-}" ] && USU_SQL="'$USUARIO_ID'" || USU_SQL="NULL"
  ORD_ID="$(
    docker compose exec -T db sh -lc "cat <<'SQL' | psql -qAtX -U ispuser -d ispdb
INSERT INTO ordenes (id,codigo,estado,tecnico_id,tipo,subtotal,total,usuario_id)
VALUES (uuid_generate_v4(), 'INS-'||extract(epoch from now())::bigint,
        'agendada', '${TECNICO_ID}', 'INS', 0, 0, ${USU_SQL})
RETURNING id;
SQL
" | tr -d '\r' | head -n1
  )"
  ORD_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_ID}'" | tr -d '\r')"
  curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/iniciar" -H 'Content-Type: application/json' | jq
  curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/${ORD_ID}/cerrar"  -H 'Content-Type: application/json' -d "{\"tecnicoId\":\"${TECNICO_ID}\"}" | jq
fi

echo "== Cerrar por CÓDIGO (idempotente) =="
curl -sS -X POST "http://127.0.0.1:3000/v1/tecnicos/${TECNICO_ID}/ordenes/codigo/${ORD_COD}/cerrar" \
  -H 'Content-Type: application/json' -d "{\"tecnicoId\":\"${TECNICO_ID}\"}" | jq

echo "== HEAD a PDF por código =="
curl -sSI "http://127.0.0.1:9000/evidencias/ordenes/${ORD_COD}.pdf" | sed -n '1,10p'
