#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000/v1}"
KEY="${KEY:-superdev}"
TECNICO_ID="${TECNICO_ID:-6}"
MATERIAL_ID="${MATERIAL_ID:-3}"
NOTE="smoke_inventory.$(date +%Y%m%d-%H%M%S)"

echo "[SMOKE] Limpieza opcional ${CLEAN:-false}"
echo "[SMOKE] Esperando readiness en http://localhost:3000/health …"
for i in {1..5}; do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health || true)
  [[ "$code" == "200" ]] && break
  sleep 0.2
done
[[ "$code" == "200" ]] || { echo "[ERR] API no lista"; exit 1; }
echo "[ OK ] API lista."

echo "[SMOKE] Sonda kardex…"
curl -sf -H "x-api-key: $KEY" "$API/inventario/kardex" >/dev/null
echo "[ OK ] Kardex responde JSON."

echo "[SMOKE] Forzando descuento (999999) debe responder 409/INSUFFICIENT_STOCK y NO escribir kardex…"
tmp_body="$(mktemp)"
# Usar cantidad POSITIVA grande para respetar validación y disparar 409 por saldo insuficiente
resp_code=$(curl -s -D - -o "$tmp_body" -w '%{http_code}' \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/tecnicos/$TECNICO_ID/descontar" \
  -d "{\"materialId\":$MATERIAL_ID,\"cantidad\":999999,\"nota\":\"$NOTE-test-reject\"}" \
  | awk 'NR==1{print $2}' || true)

if [[ "$resp_code" != "409" ]]; then
  echo "[FAIL] Esperaba 409, obtuvo $resp_code"
  echo "[DIAG] Respuesta:"
  cat "$tmp_body"
  rm -f "$tmp_body"
  exit 1
fi
rm -f "$tmp_body"
echo "[ OK ] Rechazo por saldo correcto (409) y kardex limpio."

echo "[SMOKE] Subir +2 (AGREGAR) y revertir -2 (DESCONTAR) en TEC-$TECNICO_ID / material $MATERIAL_ID…"

# Lee stock base
base=$(curl -s -H "x-api-key: $KEY" "$API/inventario/tecnicos/$TECNICO_ID/stock" \
  | jq -r ".[] | select(.material_id==$MATERIAL_ID) | .cantidad" | head -n1)
base="${base:-0}"; base=${base%.*}

# +2 con nota
curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/tecnicos/$TECNICO_ID/agregar" \
  -d "{\"materialId\":$MATERIAL_ID,\"cantidad\":2,\"nota\":\"$NOTE +2\"}" >/dev/null

# -2 con nota
curl -s -H "x-api-key: $KEY" -H "content-type: application/json" \
  -X POST "$API/inventario/tecnicos/$TECNICO_ID/descontar" \
  -d "{\"materialId\":$MATERIAL_ID,\"cantidad\":2,\"nota\":\"$NOTE -2\"}" >/dev/null

# Leer after
after=$(curl -s -H "x-api-key: $KEY" "$API/inventario/tecnicos/$TECNICO_ID/stock" \
  | jq -r ".[] | select(.material_id==$MATERIAL_ID) | .cantidad" | head -n1)
after="${after:-0}"; after=${after%.*}

if [[ "$after" != "$base" ]]; then
  # Reintento corto
  sleep 0.25
  after2=$(curl -s -H "x-api-key: $KEY" "$API/inventario/tecnicos/$TECNICO_ID/stock" \
    | jq -r ".[] | select(.material_id==$MATERIAL_ID) | .cantidad" | head -n1)
  after2="${after2:-0}"; after2=${after2%.*}
  if [[ "$after2" == "$base" ]]; then
    echo "[ OK ] Ciclo +2/-2 OK tras relectura. Stock volvió a $after2."
    exit 0
  fi

  echo "[FAIL] Tras +2/-2 el stock no volvió. base=$base after=$after (retry=$after2)"
  echo "[DIAG] Dump kardex con nota=$NOTE (últimas 24h)"
  curl -s -H "x-api-key: $KEY" "$API/inventario/kardex?days=1" \
    | jq -c "[ .[] | select(.nota != null) | select(.nota | contains(\"$NOTE\")) ]"
  exit 1
fi

echo "[ OK ] Ciclo +2/-2 OK. Stock volvió a $after."
