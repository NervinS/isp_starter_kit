#!/usr/bin/env bash
# script/smoke_ordenes_transversal.sh
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
ORD="${ORD:-INS-000001}"
PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q -At"

banner() {
  echo "=== 🧪 Smoke Órdenes – contrato transversal ==="
}

seed_if_needed() {
  ${PSQL} <<'SQL'
INSERT INTO public.ordenes (codigo, estado, tipo, subtotal, total, created_at, updated_at)
VALUES ('INS-000001','creada','INS',0,0,now(),now())
ON CONFLICT (codigo) DO NOTHING;
SQL
}

get_estado() {
  ${PSQL} <<SQL
SELECT estado FROM public.ordenes WHERE codigo='${ORD}';
SQL
}

reopen_to_agendada() {
  ${PSQL} <<SQL
UPDATE public.ordenes
   SET estado='agendada',
       agendado_para = COALESCE(agendado_para, CURRENT_DATE),
       turno = COALESCE(turno,'am'),
       cancelada_at = NULL,
       cerrada_at = NULL,
       updated_at = NOW()
 WHERE codigo='${ORD}';
SQL
}

json() { jq -r '.' >/dev/null; } # solo valida JSON

main() {
  banner
  seed_if_needed

  # Si está cerrada (o en estado no operable), reabrir a 'agendada'
  EST="$(get_estado || true)"
  case "${EST}" in
    agendada|creada|abierta|"") ;; # ok tal cual
    *) reopen_to_agendada ;;
  esac

  echo "→ GET /ordenes/${ORD}"
  curl -sf "${API}/ordenes/${ORD}" | json
  echo "OK GET shape"

  echo "→ POST /ordenes/${ORD}/evidencias (keys simuladas)"
  curl -sf -X POST "${API}/ordenes/${ORD}/evidencias" \
    -H "Content-Type: application/json" \
    -d '{"items":[{"url":"http://127.0.0.1:9000/evidencias/foto1.jpg","tipo":"instalacion"}]}' | json
  echo "OK evidencias"

  echo "→ POST /ordenes/${ORD}/equipos (prepara, no cierra)"
  # {} (no-op)
  curl -sf -X POST "${API}/ordenes/${ORD}/equipos" \
    -H "Content-Type: application/json" -d '{}' | json >/dev/null
  # { acciones: [...] }
  curl -sf -X POST "${API}/ordenes/${ORD}/equipos" \
    -H "Content-Type: application/json" \
    -d '{"acciones":[{"tipo":"reservar","equipoId":123,"cantidad":1}]}' | json >/dev/null
  # array directo
  curl -sf -X POST "${API}/ordenes/${ORD}/equipos" \
    -H "Content-Type: application/json" \
    -d '[{"tipo":"reservar","equipoId":"ONT-ABC","cantidad":2}]' | json >/dev/null
  echo "OK equipos preparar"

  echo "→ POST /ordenes/${ORD}/cerrar (idempotente)"
  curl -sf -X POST "${API}/ordenes/${ORD}/cerrar" \
    -H "Content-Type: application/json" \
    -d '{"observaciones":"OK","pdfUrl":"http://127.0.0.1:9000/evidencias/acta.pdf"}' | json

  echo "→ Retry mismo Idempotency-Key"
  # No usamos header; el endpoint es idempotente por payload/estado:
  curl -sf -X POST "${API}/ordenes/${ORD}/cerrar" \
    -H "Content-Type: application/json" \
    -d '{"observaciones":"OK"}' | json
}

main "$@"
