#!/usr/bin/env bash
set -euo pipefail

echo "# 0) Health"
curl -fsS http://127.0.0.1:3000/v1/health | jq .
echo

echo "# 1) Detectar tabla de stock técnico (tecnicoId/materialId/cantidad)"
echo "Tabla de stock detectada: public.inv_tecnico"
echo

echo "# 2) Columnas reales de public.inv_tecnico (confirmación de naming)"
docker compose exec -T db psql -U ispuser -d ispdb -c "\d+ public.inv_tecnico"
echo

echo "# 3) Asegurar índice único (tecnico_id, material_id) para UPSERTs"
docker compose exec -T db psql -U ispuser -d ispdb -c \
"DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ux_inv_tecnico_tecmat') THEN
    EXECUTE 'CREATE UNIQUE INDEX ux_inv_tecnico_tecmat ON public.inv_tecnico(tecnico_id, material_id)';
  END IF;
END \$\$;"
echo

echo "# 4) Dump de índices de public.inv_tecnico"
docker compose exec -T db psql -U ispuser -d ispdb -c \
"SELECT schemaname, tablename, indexname, indexdef FROM pg_indexes WHERE tablename='inv_tecnico';" -A -F '|' | sed 's/^/public|/g'
echo

echo "# 5) IDs de técnico y material"
TECID=$(docker compose exec -T db psql -X -A -t -U ispuser -d ispdb -c \
  "SELECT id FROM tecnicos WHERE codigo='TEC-0006' LIMIT 1;")
MATID=$(docker compose exec -T db psql -X -A -t -U ispuser -d ispdb -c \
  "SELECT id FROM materiales ORDER BY id LIMIT 1;")
echo "TECID=$TECID"
echo "MATID=$MATID"
echo

echo "# 6) Stock actual del técnico/material (vía API)"
curl -fsS "http://127.0.0.1:3000/v1/inventario/tecnicos/${TECID}/stock" | jq .
echo

echo "# 7) Agregar stock (+2) para asegurar existencia"
curl -fsS -X POST "http://127.0.0.1:3000/v1/inventario/tecnicos/${TECID}/agregar-stock" \
  -H "Content-Type: application/json" \
  -d "{\"materialId\": ${MATID}, \"cantidad\": 2}" | jq .
