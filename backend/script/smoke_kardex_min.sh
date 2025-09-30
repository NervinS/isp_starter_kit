#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:3000/v1"

say(){ echo -e "$@"; }
psqlc(){ docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 -c "$1"; }

say "=== 📒 Smoke Kardex (mínimo) ==="

say "⏳ Esperando API..."
for i in {1..60}; do curl -sf "$API/health" >/dev/null && break || sleep 1; done
curl -s "$API/health" | jq -r '.status?' || true

say "🔧 Bootstrap BD (por si acaso)..."
docker compose exec -T db psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 < script/bootstrap_db_v2.sql

say "🧪 Asegurar al menos 2 movimientos (ingreso y ajuste) para almacén técnico 6/material 3"
psqlc "
WITH a AS (
  SELECT id AS almacen_id FROM almacenes WHERE tipo='tecnico' AND tecnico_id=6 LIMIT 1
)
INSERT INTO movimientos (tipo, almacen_destino_id, material_id, cantidad)
SELECT 'ingreso', a.almacen_id, 3, 2 FROM a
UNION ALL
SELECT 'ajuste', a.almacen_id, 3, 1 FROM a
ON CONFLICT DO NOTHING;
"

say "🔎 GET /v1/inventario/kardex"
RES="$(curl -s -w '\n%{http_code}' "$API/inventario/kardex")"
BODY="$(echo "$RES" | head -n -1)"
CODE="$(echo "$RES" | tail -n 1)"
echo "$BODY" | jq . || true

if [[ "$CODE" != "200" ]]; then
  say "❌ HTTP $CODE en /kardex"
  exit 1
fi

COUNT="$(echo "$BODY" | jq 'length // 0')"
if [[ "$COUNT" -ge 1 ]]; then
  say "🎉 Smoke Kardex mínimo OK (items=$COUNT)"
  exit 0
else
  say "❌ Esperaba >=1 ítems, obtuve $COUNT"
  exit 1
fi
