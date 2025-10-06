\set ON_ERROR_STOP on
SET search_path=public;

\echo '=== Resumen: diferencias stock (teórica vs real) ==='
WITH ing AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ingreso' AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), egr AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='egreso' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ap AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste' AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), an AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ti AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), to2 AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr USING (almacen_id, material_id)
  FULL JOIN ap  USING (almacen_id, material_id)
  FULL JOIN an  USING (almacen_id, material_id)
  FULL JOIN ti  USING (almacen_id, material_id)
  FULL JOIN to2 USING (almacen_id, material_id)
)
SELECT COUNT(*) AS diffs
FROM (
  SELECT t.almacen_id, t.material_id, t.teorica, s.cantidad AS real
  FROM tot t
  JOIN stock_almacen s USING (almacen_id, material_id)
  WHERE COALESCE(t.teorica,0) <> COALESCE(s.cantidad,0)
) z;

\echo E'\n=== Detalle de diferencias (top 50 por |delta|) ==='
WITH ing AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ingreso' AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), egr AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='egreso' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ap AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste' AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), an AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo='ajuste' AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), ti AS (
  SELECT m.to_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.to_almacen_id IS NOT NULL
  GROUP BY 1,2
), to2 AS (
  SELECT m.from_almacen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM movimientos m
  WHERE m.tipo IN ('traslado','transferencia') AND m.from_almacen_id IS NOT NULL
  GROUP BY 1,2
), tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0)-COALESCE(egr.qty,0)+COALESCE(ap.qty,0)-COALESCE(an.qty,0)+COALESCE(ti.qty,0)-COALESCE(to2.qty,0) AS teorica
  FROM ing
  FULL JOIN egr USING (almacen_id, material_id)
  FULL JOIN ap  USING (almacen_id, material_id)
  FULL JOIN an  USING (almacen_id, material_id)
  FULL JOIN ti  USING (almacen_id, material_id)
  FULL JOIN to2 USING (almacen_id, material_id)
)
SELECT a.codigo, t.material_id, COALESCE(s.cantidad,0) AS real, t.teorica,
       (COALESCE(s.cantidad,0)-t.teorica) AS delta
FROM tot t
LEFT JOIN stock_almacen s USING (almacen_id, material_id)
JOIN almacenes a ON a.id = t.almacen_id
WHERE COALESCE(s.cantidad,0) <> t.teorica
ORDER BY ABS(COALESCE(s.cantidad,0)-t.teorica) DESC, a.codigo, t.material_id
LIMIT 50;
