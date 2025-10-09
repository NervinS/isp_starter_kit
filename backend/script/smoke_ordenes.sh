# script/smoke_ordenes.sh
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
PSQL="docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -X -q -At"

banner() {
  echo "=== 🧪 smoke_ordenes ==="
  echo "API=${API}"
}

pick_open_order() {
  ${PSQL} <<'SQL'
SELECT codigo
FROM ordenes
WHERE tipo='INS'
  AND estado IN ('creada','abierta','agendada')
ORDER BY created_at DESC NULLS LAST
LIMIT 1;
SQL
}

pick_latest_any_state() {
  ${PSQL} <<'SQL'
SELECT codigo
FROM ordenes
WHERE tipo='INS'
ORDER BY created_at DESC NULLS LAST
LIMIT 1;
SQL
}

reopen_order_to_agendada() {
  local cod="$1"
  ${PSQL} <<SQL
UPDATE ordenes
   SET estado='agendada',
       agendado_para = COALESCE(agendado_para, CURRENT_DATE),
       turno = COALESCE(turno,'am'),
       cancelada_at = NULL,
       cerrada_at = NULL,
       updated_at = NOW()
 WHERE codigo='${cod}';
SQL
}

get_estado() {
  local cod="$1"
  ${PSQL} <<SQL
SELECT estado FROM ordenes WHERE codigo='${cod}';
SQL
}

get_turno() {
  local cod="$1"
  ${PSQL} <<SQL
SELECT turno FROM ordenes WHERE codigo='${cod}';
SQL
}

get_agendado_para() {
  local cod="$1"
  ${PSQL} <<SQL
SELECT to_char(agendado_para::date,'YYYY-MM-DD')
FROM ordenes
WHERE codigo='${cod}';
SQL
}

main() {
  banner
  # 1) intenta tomar una INS operable
  ORD="$(pick_open_order || true)"
  if [[ -z "${ORD}" ]]; then
    # 2) si no hay abierta, toma la última INS (aunque esté cerrada/anulada)
    ORD="$(pick_latest_any_state || true)"
    if [[ -z "${ORD}" ]]; then
      echo "❌ No hay órdenes de tipo INS en la base. Sube un fixture y reintenta."
      exit 1
    fi
    echo "ℹ️  No había INS abiertas; reabriendo ${ORD} → estado=agendada (modo DB)…"
    reopen_order_to_agendada "${ORD}"
    # 3) validar que quedó operable
    EST="$(get_estado "${ORD}")"
    if [[ "${EST}" != "agendada" ]]; then
      echo "❌ No pude reabrir ${ORD} (estado actual=${EST})."
      exit 1
    fi
  fi

  EST="$(get_estado "${ORD}")"
  TURNO="$(get_turno "${ORD}")"
  FECHA="$(get_agendado_para "${ORD}")"

  echo "→ Usando orden ${ORD}"
  echo "   estado=${EST}  turno=${TURNO:--}  agendado_para=${FECHA:--}"

  # Si llegamos aquí, la orden es operable para pruebas de agenda/asignación posteriores
  echo "✅ smoke_ordenes OK"
}

main "$@"
