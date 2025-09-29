#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Smoke de Inventario (v1)
# =========================
# Requisitos:
#  - stack arriba: docker compose up -d db minio api
#  - TOKEN=devtoken (o tu token) en el entorno
#  - API accesible en http://127.0.0.1:3000 (ajustable)
#
# Qué valida:
#  1) API saludable y rutas mapeadas
#  2) Descubre almacenes principal/técnico
#  3) Transferencia 10 del principal -> técnico
#  4) Idempotencia (repetir misma key no cambia saldos)
#  5) Egreso con saldo insuficiente -> 409
#  6) Sin desvíos (v_desviacion_inv_tecnico)
#
# Notas:
#  - Todas las operaciones usan cantidades EN ENTEROS.
#  - Evitamos aritmética con decimales en Bash.

API="${API:-http://127.0.0.1:3000}"
AUTH="Authorization: Bearer ${TOKEN:?Falta TOKEN en el entorno}"
MAT_ONT="${MAT_ONT:-3}"         # material a usar (ONT)
IDEMP="smoke-$(date +%s)"

# Función: esperar a que /v1/health responda HTTP 200
wait_health() {
  echo -e "\n== Esperando /v1/health"
  for i in {1..60}; do
    if curl -sf "$API/v1/health" >/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  echo "❌ API no respondió /v1/health en tiempo"
  exit 1
}

# Función de query psql que retorna una sola línea formateada
psql1() {
  docker compose exec -T db psql -U ispuser -d ispdb -tA -F '|' -c "$1"
}

# 1) Health
wait_health

# 2) Verificar rutas de inventario mapeadas (opcional pero útil)
echo -e "\n== Verificando que las rutas de Inventario estén mapeadas"
curl -sf -H "$AUTH" "$API/v1/inventario/stock?scope=principal" >/dev/null || {
  echo "❌ No responde /v1/inventario/stock (¿TOKEN correcto?, ¿rutas cargadas?)"
  exit 1
}

# 3) Descubrir almacenes principal/técnico (sin MAX(uuid))
echo -e "\n== Descubriendo almacenes principal/técnico"
read ALM_PRI ALM_TEC < <(psql1 "
  WITH p AS (
    SELECT id AS principal FROM almacenes WHERE tipo='principal' LIMIT 1
  ), t AS (
    SELECT id AS tecnico   FROM almacenes WHERE tipo='tecnico'   LIMIT 1
  )
  SELECT p.principal::text || ' ' || t.tecnico::text FROM p,t;
")
if [[ -z "${ALM_PRI:-}" || -z "${ALM_TEC:-}" ]]; then
  echo "❌ No se encontraron almacenes principal/técnico"
  exit 1
fi

# Validación de UUIDs
re_uuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
[[ "$ALM_PRI" =~ $re_uuid ]] || { echo "❌ UUID inválido ALM_PRI='$ALM_PRI'"; exit 1; }
[[ "$ALM_TEC" =~ $re_uuid ]] || { echo "❌ UUID inválido ALM_TEC='$ALM_TEC'"; exit 1; }

echo "API=$API"
echo "ALM_PRI=$ALM_PRI"
echo "ALM_TEC=$ALM_TEC"
echo "MAT_ONT=$MAT_ONT"
echo "IDEMP=$IDEMP"

# 4) Esperar /inventario/stock con auth
echo -e "\n== Esperando /v1/inventario/stock?scope=principal (con auth)"
for i in {1..60}; do
  if curl -sf -H "$AUTH" "$API/v1/inventario/stock?scope=principal" >/dev/null; then
    break
  fi
  sleep 0.5
done

# Helper: snapshot de cantidades como ENTEROS
snapshot() {
  psql1 "
    WITH s AS (
      SELECT a.id, a.tipo, COALESCE(s.cantidad,0)::bigint AS cantidad
      FROM   almacenes a
      LEFT JOIN stock_almacen s ON s.almacen_id=a.id AND s.material_id=${MAT_ONT}
      WHERE  a.id IN ('${ALM_PRI}','${ALM_TEC}')
    )
    SELECT
      COALESCE(MAX(cantidad) FILTER (WHERE tipo='principal'),0)::text || '|' ||
      COALESCE(MAX(cantidad) FILTER (WHERE tipo='tecnico'),0)::text
    FROM s;
  "
}

# 5) Snapshot inicial
echo -e "\n== Snapshot inicial"
IFS='|' read P0 T0 < <(snapshot)
echo "principal=$P0 tecnico=$T0"

# 6) Transferencia 10 p->t
echo -e "\n== Transferencia 10 principal->tecnico"
XFER_BODY=$(jq -n --arg idem "$IDEMP" --arg o "$ALM_PRI" --arg d "$ALM_TEC" --argjson mid $MAT_ONT --argjson qty 10 \
  '{idempotencyKey:$idem,tipo:"transferencia",almacenOrigenId:$o,almacenDestinoId:$d,materialIdInt:$mid,cantidad:$qty}')
curl -sS -H "$AUTH" -H "Content-Type: application/json" -d "$XFER_BODY" \
  "$API/v1/inventario/movimientos" | jq .

# 7) Snapshot post-transferencia
echo -e "\n== Snapshot post-transferencia"
IFS='|' read P1 T1 < <(snapshot)
echo "principal=$P1 tecnico=$T1"

# Validaciones aritméticas (ENTEROS)
if (( P1 != P0 - 10 )); then
  echo "❌ principal esperado=$((P0-10)) got=$P1"
  exit 1
fi
if (( T1 != T0 + 10 )); then
  echo "❌ tecnico esperado=$((T0+10)) got=$T1"
  exit 1
fi

# 8) Espejo inv_tecnico sin desvío
echo -e "\n== Espejo inv_tecnico sin desvío"
docker compose exec -T db psql -U ispuser -d ispdb -c "
  SELECT * FROM v_desviacion_inv_tecnico
  WHERE material_id=${MAT_ONT} AND diff<>0
  ORDER BY tecnico_id, material_id;
" | sed 's/^/  /'

# 9) Idempotencia: reintento misma key
echo -e "\n== Reintento idempotente (misma key)"
curl -sS -H "$AUTH" -H "Content-Type: application/json" -d "$XFER_BODY" \
  "$API/v1/inventario/movimientos" | jq .

# Snapshot tras reintento (debe igual al post)
echo -e "\n== Snapshot tras reintento (debe ser igual al post)"
IFS='|' read P2 T2 < <(snapshot)
echo "principal=$P2 tecnico=$T2"
if (( P2 != P1 || T2 != T1 )); then
  echo "❌ Idempotencia rota: post=($P1,$T1) reintento=($P2,$T2)"
  exit 1
fi

# 10) Egreso con saldo insuficiente (desde principal)
echo -e "\n== Egreso con saldo insuficiente (debe 409)"
EGRESO_Q=$((P2 + 1)) # pedimos más de lo que hay
EGRESO_BODY=$(jq -n --arg idem "${IDEMP}-egreso" --arg o "$ALM_PRI" --argjson mid $MAT_ONT --argjson qty $EGRESO_Q \
  '{idempotencyKey:$idem,tipo:"egreso",almacenOrigenId:$o,materialIdInt:$mid,cantidad:$qty}')
HTTP=$(curl -sS -o /tmp/egreso.json -w "%{http_code}" -H "$AUTH" -H "Content-Type: application/json" \
  -d "$EGRESO_BODY" "$API/v1/inventario/movimientos" || true)
if [[ "$HTTP" != "409" ]]; then
  echo "❌ Debe responder 409 por saldo insuficiente (got='$HTTP' exp='409')"
  echo "Cuerpo:"
  cat /tmp/egreso.json
  # No abortamos aquí para seguir viendo desvíos; comenta 'exit 1' si prefieres que corte.
  exit 1
else
  echo "✔ 409 correcto"
fi

echo -e "\n== Smoke OK"
