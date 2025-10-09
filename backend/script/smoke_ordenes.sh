#!/usr/bin/env bash
# script/smoke_ordenes.sh
# Smoke de órdenes: GET -> evidencias -> cerrar (idempotente) -> GET final
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
API="${API_BASE%/}/v1"
KEY="${KEY:-superdev}"

say() { echo -e "$@"; }

curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  local data="${1-}"; shift || true

  if [[ -n "${data}" ]]; then
    curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" \
      -X "${method}" -d "${data}" "${url}"
  else
    curl -sfS -H "x-api-key: ${KEY}" "${url}"
  fi
}

jq_ok() {
  # evalúa un filtro jq que debe devolver algo “truthy”, o falla
  local filter="$1"
  if ! jq -e "${filter}" >/dev/null; then
    return 1
  fi
}

say "=== 🧪 smoke_ordenes ==="
say "API=${API}"

# 1) Elegir una orden candidata (no anulada, no cerrada)
list_json="$(curl_json GET "${API}/ordenes")"
# Preferimos estados operables
COD="$(echo "${list_json}" | jq -r '
  ( [.[] | select(.estado != "anulada" and .estado != "cerrada"
                  and (.estado == "agendada" or .estado == "programada" or .estado == "iniciada"))]
    + [.[] | select(.estado != "anulada" and .estado != "cerrada")] )
  | .[0].codigo // empty
')"

if [[ -z "${COD}" || "${COD}" == "null" ]]; then
  echo "❌ No hay órdenes candidatas para smoke (todas están anuladas/cerradas)."
  echo "   Sube algún fixture o crea una orden operable antes de correr este smoke."
  exit 1
fi

say "→ Usando orden ${COD}"

# 2) GET /ordenes/:codigo
curl_json GET "${API}/ordenes/${COD}" | jq_ok ".codigo == \"${COD}\"" || {
  echo "❌ GET /ordenes/${COD} no devolvió la orden esperada"
  exit 1
}

# 3) POST evidencias (acepta camel o snake; aquí usamos snake)
evid_payload="$(jq -n --arg f "evidencias/ordenes/SMOKE/firma.png" \
                    --arg p "evidencias/ordenes/SMOKE/foto1.jpg" \
                    '{firma_key:$f, foto1_key:$p}')"

post_ev_json="$(curl_json POST "${API}/ordenes/${COD}/evidencias" "${evid_payload}")"
echo "${post_ev_json}" | jq_ok '.ok == true' || { echo "❌ evidencias -> ok != true"; exit 1; }
echo "${post_ev_json}" | jq_ok ".codigo == \"${COD}\"" || { echo "❌ evidencias -> codigo mismatch"; exit 1; }
echo "${post_ev_json}" | jq_ok '.firmaKey and (.evidencias.foto1Key // .evidencias["foto1_key"])' || {
  echo "❌ evidencias -> faltan claves esperadas"; exit 1;
}

# 4) PUT cerrar (con Idempotency-Key)
IDEM="smoke-${COD}-$(date +%s%3N)"
cierre_payload='{"comentarios":"cierre smoke","materiales":[],"equipos":{"asignar":[],"retirar":[]}}'

put_close_json="$(curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" \
  -H "Idempotency-Key: ${IDEM}" -X PUT -d "${cierre_payload}" "${API}/ordenes/${COD}/cerrar")"

# Primer intento: ok true, y si no era cerrada antes, debe venir estado=cerrada.
echo "${put_close_json}" | jq_ok '.ok == true' || { echo "❌ cerrar -> ok != true"; exit 1; }

# Si el backend marca el primer intento con _idempotent false/ausente, validamos estado=cerrada
if ! echo "${put_close_json}" | jq -e '._idempotent == true' >/dev/null 2>&1; then
  echo "${put_close_json}" | jq_ok '.estado == "cerrada" and (.cerradaAt != null)' || {
    echo "❌ cerrar -> estado != cerrada o faltó cerradaAt"; exit 1;
  }
fi

# 5) Reintento idempotente
put_close_json2="$(curl -sfS -H "x-api-key: ${KEY}" -H "content-type: application/json" \
  -H "Idempotency-Key: ${IDEM}" -X PUT -d "${cierre_payload}" "${API}/ordenes/${COD}/cerrar")"

echo "${put_close_json2}" | jq_ok '.ok == true' || { echo "❌ cerrar (retry) -> ok != true"; exit 1; }
echo "${put_close_json2}" | jq_ok '._idempotent == true' || {
  echo "❌ cerrar (retry) -> no vino _idempotent=true"; exit 1;
}

# 6) GET final para confirmar estado
curl_json GET "${API}/ordenes/${COD}" | jq_ok '.estado == "cerrada"' || {
  echo "❌ GET final -> la orden no quedó cerrada"; exit 1;
}

say "✅ smoke_ordenes OK"
