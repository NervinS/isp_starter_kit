#!/usr/bin/env bash
# script/reconcile_inventory.sh
# Verifica consistencia entre stock_almacen (real) y el stock teórico derivado de movimientos.
# - Muestra resumen (conteo de diffs)
# - Si hay diferencias, muestra detalle (top 50 por |delta|)
#
# Uso:
#   ./script/reconcile_inventory.sh
#
# Requisitos: estar dentro de /backend (o ejecutarlo desde la raíz del repo).
set -euo pipefail

# Detecta si estamos en /backend o en la raíz del repo
if [[ -f "./docker-compose.yml" && -f "./docker-compose.override.yml" ]]; then
  # estamos dentro de backend/
  COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.override.yml"
elif [[ -f "./backend/docker-compose.yml" && -f "./backend/docker-compose.override.yml" ]]; then
  # estamos en la raíz del repo
  COMPOSE_ARGS="-f backend/docker-compose.yml -f backend/docker-compose.override.yml"
  cd backend
else
  echo "❌ No encuentro docker-compose.yml. Ejecuta este script desde la raíz del repo o dentro de /backend."
  exit 1
fi

PSQL="docker compose ${COMPOSE_ARGS} exec -T db psql -U ispuser -d ispdb -At -c"

SQL_SUMMARY="$(cat <<'SQL'
WITH ing AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), egr AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ap AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), an AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ti AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), to2 AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr  USING (almacen_id, material_id)
  FULL JOIN ap   USING (almacen_id, material_id)
  FULL JOIN an   USING (almacen_id, material_id)
  FULL JOIN ti   USING (almacen_id, material_id)
  FULL JOIN to2  USING (almacen_id, material_id)
)
SELECT COUNT(*)::int
FROM tot t
JOIN stock_almacen sa USING (almacen_id, material_id)
WHERE COALESCE(sa.cantidad,0) <> t.teorica;
SQL
)"

SQL_DETAIL="$(cat <<'SQL'
WITH ing AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ingreso'  AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), egr AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='egreso'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ap AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), an AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste'   AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ti AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='traslado' AND m.to_almacen_id  IS NOT NULL
  GROUP BY 1,2
), to2 AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='traslado' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr  USING (almacen_id, material_id)
  FULL JOIN ap   USING (almacen_id, material_id)
  FULL JOIN an   USING (almacen_id, material_id)
  FULL JOIN ti   USING (almacen_id, material_id)
  FULL JOIN to2  USING (almacen_id, material_id)
)
SELECT a.codigo, t.material_id,
       sa.cantidad AS real, t.teorica,
       (t.teorica - sa.cantidad) AS delta
FROM tot t
JOIN stock_almacen sa USING (almacen_id, material_id)
JOIN almacenes a ON a.id = t.almacen_id
WHERE COALESCE(sa.cantidad,0) <> t.teorica
ORDER BY ABS(t.teorica - sa.cantidad) DESC
LIMIT 50;
SQL
)"

echo "=== 🔎 Consistency Check (stock vs movimientos) ==="
diffs="$($PSQL "$SQL_SUMMARY" | tr -d '\r')"
echo "Differences: ${diffs}"

if [[ "${diffs}" != "0" ]]; then
  echo
  echo "=== Detalle (top 50 por |delta|) ==="
  $PSQL "$SQL_DETAIL" | sed 's/|/  |  /g'
  exit 2
else
  echo "✅ Consistency OK (no diffs)"
fi
