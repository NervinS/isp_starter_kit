# script/smoke_ordenes_all_types.sh
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q -At"

# Tipos soportados por el CHECK de la tabla:
TIPOS=("INS" "MAN" "COR" "REC" "BAJ" "TRA" "CMB" "RCT")

banner() {
  echo "=== 🧪 smoke_ordenes_all_types ==="
  echo "API=${API}"
}

seed_tipo() {
  local tipo="$1"
  local cod="${tipo}-000001"
  ${PSQL} <<SQL
INSERT INTO public.ordenes (codigo, estado, tipo, subtotal, total, created_at, updated_at)
VALUES ('${cod}', 'creada', '${tipo}', 0, 0, now(), now())
ON CONFLICT (codigo) DO NOTHING;
SQL
  echo "${cod}"
}

test_orden() {
  local cod="$1"

  echo "→ ${cod} :: GET"
  curl -sf "${API}/ordenes/${cod}" >/dev/null

  echo "→ ${cod} :: evidencias"
  curl -sf -X POST "${API}/ordenes/${cod}/evidencias" \
    -H "Content-Type: application/json" \
    -d '{"items":[{"url":"http://127.0.0.1:9000/evidencias/foto.jpg","tipo":"instalacion"}]}' >/dev/null

  echo "→ ${cod} :: equipos {}"
  curl -sf -X POST "${API}/ordenes/${cod}/equipos" \
    -H "Content-Type: application/json" -d '{}' >/dev/null

  echo "→ ${cod} :: equipos {acciones:[...]}"
  curl -sf -X POST "${API}/ordenes/${cod}/equipos" \
    -H "Content-Type: application/json" \
    -d '{"acciones":[{"tipo":"reservar","equipoId":123,"cantidad":1}]}' >/dev/null

  echo "→ ${cod} :: cerrar (idempotente x2)"
  curl -sf -X POST "${API}/ordenes/${cod}/cerrar" \
    -H "Content-Type: application/json" \
    -d '{"observaciones":"OK","pdfUrl":"http://127.0.0.1:9000/evidencias/acta.pdf"}' >/dev/null
  curl -sf -X POST "${API}/ordenes/${cod}/cerrar" \
    -H "Content-Type: application/json" \
    -d '{"observaciones":"OK"}' >/dev/null

  echo "→ ${cod} :: ver estado final"
  curl -sf "${API}/ordenes/${cod}" | jq -r '
    select(.estado=="cerrada") | "OK estado=cerrada cerradaAt=\(.cerradaAt) tipo=\(.tipo)"' >/dev/null

  echo "✅ ${cod} OK"
}

main() {
  banner
  for t in "${TIPOS[@]}"; do
    cod="$(seed_tipo "${t}")"
    test_orden "${cod}"
  done
  echo "🎉 smoke_ordenes_all_types OK"
}

main "$@"
