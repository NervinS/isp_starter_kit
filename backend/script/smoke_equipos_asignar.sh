#!/usr/bin/env bash
# script/smoke_equipos_asignar.sh
# Smoke: entregar 1 equipo (ONU por defecto) desde ALM-PRINC a TEC-6.
# - Auto-reabastece si no hay stock en ALM-PRINC reciclando 1 ONU desde un técnico.
# - Reabastecimiento idempotente y acotado (máx 1).
# - Entrega idempotente con Idempotency-Key.
# - Sale OK si realmente no hay nada que hacer.

set -euo pipefail

# ===== Config =====
API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"

TIPO="${TIPO:-ONU}"                 # Puedes cambiar a REPETIDOR si quieres probar otra cosa
TECNICO_ID="${TECNICO_ID:-6}"
FROM_ALMACEN="${FROM_ALMACEN:-ALM-PRINC}"

# Conexión DB (para el reabastecimiento controlado)
DC="${DC:-docker compose}"          # o "docker-compose" si usas el binario viejo
DB_SERVICE="${DB_SERVICE:-db}"      # nombre del servicio en docker compose
DB_USER="${DB_USER:-ispuser}"
DB_NAME="${DB_NAME:-ispdb}"

IDK="SMK-EQ-ENT-${TIPO}-$(date +%s)"

say(){ echo -e "$@"; }

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1-}"
  if [[ -n "${data}" ]]; then
    curl -sfS -H "x-api-key: ${KEY}" \
         -H "content-type: application/json" \
         -H "Idempotency-Key: ${IDK}" \
         -X "${method}" -d "${data}" "${url}"
  else
    curl -sfS -H "x-api-key: ${KEY}" \
         -H "Idempotency-Key: ${IDK}" \
         -X "${method}" "${url}"
  fi
}

reabastecer_si_falta() {
  # Solo aplica a TIPO=ONU, por ahora. Si quieres soportar otros tipos, habría que definir
  # una política similar para REPETIDOR.
  [[ "${TIPO}" != "ONU" ]] && return 0

  say "No hay ONU en almacén; intentando reciclar 1 desde un técnico…"
  ${DC} exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d "${DB_NAME}" <<'SQL' >/dev/null || true
WITH no_onu_en_almacen AS (
  SELECT COUNT(*) = 0 AS ok
  FROM equipos
  WHERE tipo='ONU' AND estado='EN_STOCK' AND owner_tipo='ALMACEN'
),
picked AS (
  SELECT e.id
  FROM equipos e, no_onu_en_almacen chk
  WHERE chk.ok
    AND e.tipo='ONU' AND e.estado='EN_STOCK' AND e.owner_tipo='TECNICO'
  ORDER BY e.created_at DESC
  LIMIT 1
)
UPDATE equipos e
SET owner_tipo='ALMACEN',
    owner_id='ALM-PRINC'
FROM picked p
WHERE e.id = p.id;
SQL
}

# ===== Flow =====
say "== equipos: entregar (tipo=${TIPO}) =="

# 1) Consultar disponibles en almacén
DISP_JSON="$(curl_json GET "${API}/equipos/disponibles?tipo=${TIPO}")" || DISP_JSON="[]"
COUNT="$(jq -r 'length' <<<"${DISP_JSON}")"

if [[ "${COUNT}" -eq 0 ]]; then
  # Intentar reabastecer (solo ONU implementado)
  reabastecer_si_falta
  # Reintentar consulta
  DISP_JSON="$(curl_json GET "${API}/equipos/disponibles?tipo=${TIPO}")" || DISP_JSON="[]"
  COUNT="$(jq -r 'length' <<<"${DISP_JSON}")"
fi

if [[ "${COUNT}" -eq 0 ]]; then
  say "No hay ${TIPO} en almacén y no hay unidades para reciclar. OK (nada que hacer)."
  exit 0
fi

EID="$(jq -r '.[0].id' <<<"${DISP_JSON}")"
say "Usando equipo id=${EID}"

# 2) Entregar al técnico (fromAlmacen explícito)
BODY="$(jq -n --arg id "${EID}" --argjson tec "${TECNICO_ID}" --arg fa "${FROM_ALMACEN}" \
        '{id:$id, tecnicoId:$tec, fromAlmacen:$fa}')"

R1="$(curl_json POST "${API}/equipos/entregar" "${BODY}")"
jq -r '{
  ok,
  from,
  to_len: ( (.to // []) | length ),
  _idempotent
}' <<< "${R1}"

# 3) Reintento idempotente con misma key (no-op esperado)
R2="$(curl_json POST "${API}/equipos/entregar" "${BODY}")"
jq -r '{
  ok,
  from,
  to_len: ( (.to // []) | length ),
  _idempotent
}' <<< "${R2}"

# 4) Post-check (muestra el primer disponible si aún queda stock)
POST_CHECK="$(curl_json GET "${API}/equipos/disponibles?tipo=${TIPO}" || true)"
jq -r 'if (type=="array" and length>0) then .[0] else empty end' <<< "${POST_CHECK}" || true
