#!/usr/bin/env bash
set -euo pipefail

# Siempre ejecutar desde backend
BASE="/home/yarumo/isp_starter_kit/backend"; [ -d "$BASE" ] || BASE="/root/isp_starter_kit/backend"
cd "$BASE"
echo "📁 CWD: $(pwd)"

psqlq='docker compose exec -T db psql -qAtX -U ispuser -d ispdb -c'

# ==== IDs base (técnico y usuario cualquiera) ====
TECNICO_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;" | tr -d '\r')"
USUARIO_ID="$($psqlq "SELECT COALESCE((SELECT usuario_id FROM ordenes WHERE usuario_id IS NOT NULL LIMIT 1),
                                      (SELECT id FROM usuarios LIMIT 1));" | tr -d '\r' || true)"
[ -n "${TECNICO_ID:-}" ] || { echo "❌ No hay técnico"; exit 1; }
echo "👷 TECNICO_ID=${TECNICO_ID}  👤 USUARIO_ID=${USUARIO_ID:-<NULL>}"

# ==== Fechas/turnos ====
tomorrow="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
day2="$(date -u -d '+2 day' +%F 2>/dev/null || date -u -v+2d +%F)"
turno_am="am"
turno_pm="pm"

# ==== Helper para insertar orden ====
new_order() {
  if [ -n "${USUARIO_ID:-}" ]; then USUARIO_SQL="'${USUARIO_ID}'"; else USUARIO_SQL="NULL"; fi
  docker compose exec -T db sh -lc "
    psql -qAtX -U ispuser -d ispdb -c \"
      INSERT INTO ordenes (id, codigo, estado, tecnico_id, tipo, subtotal, total, usuario_id)
      VALUES (
        uuid_generate_v4(),
        'INS-' || extract(epoch from clock_timestamp())::bigint || '-' ||
        substr(replace(uuid_generate_v4()::text,'-',''),1,4),
        'agendada', '${TECNICO_ID}', 'INS', 0, 0, ${USUARIO_SQL}
      )
      RETURNING id;
    \"
  " | tr -d '\r' | head -n1
}

# ==== A) Asignar ====
ORD_ID="$(new_order)"
[ -n "${ORD_ID}" ] || { echo "❌ No se pudo crear orden"; exit 1; }
ORD_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_ID}'" | tr -d '\r')"
echo "🆕 Orden A: ${ORD_COD}"

echo "== ASIGNAR =="
curl -sS -X POST "http://127.0.0.1:3000/v1/agenda/ordenes/${ORD_COD}/asignar" \
  -H 'Content-Type: application/json' \
  -d "{\"fecha\":\"${tomorrow}\",\"turno\":\"${turno_am}\",\"tecnicoId\":\"${TECNICO_ID}\"}" | jq

echo "DB -> $($psqlq "SELECT codigo, estado, agendado_para, turno, agendada_at FROM ordenes WHERE id='${ORD_ID}'" | tr -d '\r')"

# ==== B) Reagendar ====
echo "== REAGENDAR =="
curl -sS -X POST "http://127.0.0.1:3000/v1/agenda/ordenes/${ORD_COD}/reagendar" \
  -H 'Content-Type: application/json' \
  -d "{\"fecha\":\"${day2}\",\"turno\":\"${turno_pm}\"}" | jq

echo "DB -> $($psqlq "SELECT codigo, estado, agendado_para, turno, agendada_at FROM ordenes WHERE id='${ORD_ID}'" | tr -d '\r')"

# ==== C) Cancelar ====
ORD_B_ID="$(new_order)"
ORD_B_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_B_ID}'" | tr -d '\r')"
echo "🆕 Orden B (para cancelar): ${ORD_B_COD}"

curl -sS -X POST "http://127.0.0.1:3000/v1/agenda/ordenes/${ORD_B_COD}/cancelar" \
  -H 'Content-Type: application/json' \
  -d '{"motivo":"Cliente no está"}' | jq

echo "DB -> $($psqlq "SELECT codigo, estado, motivo_cancelacion, cancelada_at FROM ordenes WHERE id='${ORD_B_ID}'" | tr -d '\r')"

# ==== D) Anular ====
ORD_C_ID="$(new_order)"
ORD_C_COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${ORD_C_ID}'" | tr -d '\r')"
echo "🆕 Orden C (para anular): ${ORD_C_COD}"

curl -sS -X POST "http://127.0.0.1:3000/v1/agenda/ordenes/${ORD_C_COD}/anular" \
  -H 'Content-Type: application/json' \
  -d '{"motivo":"No hay cobertura"}' | jq

echo "DB -> $($psqlq "SELECT codigo, estado, motivo_codigo, anulada_at FROM ordenes WHERE id='${ORD_C_ID}'" | tr -d '\r')"

echo "✅ Smoke Agenda OK"
