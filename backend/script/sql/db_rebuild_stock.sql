BEGIN;

TRUNCATE public.stock_almacen;

WITH
ing AS (
  SELECT m.almacen_destino_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='ingreso' AND m.almacen_destino_id IS NOT NULL
  GROUP BY 1,2
),
egr AS (
  SELECT m.almacen_origen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='egreso' AND m.almacen_origen_id IS NOT NULL
  GROUP BY 1,2
),
ap AS (
  SELECT m.almacen_destino_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='ajuste' AND m.almacen_destino_id IS NOT NULL
  GROUP BY 1,2
),
an AS (
  SELECT m.almacen_origen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='ajuste' AND m.almacen_origen_id IS NOT NULL
  GROUP BY 1,2
),
ti AS (
  SELECT m.almacen_destino_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='traslado' AND m.almacen_destino_id IS NOT NULL
  GROUP BY 1,2
),
to2 AS (
  SELECT m.almacen_origen_id almacen_id, m.material_id, SUM(m.cantidad)::int qty
  FROM public.movimientos m
  WHERE m.tipo='traslado' AND m.almacen_origen_id IS NOT NULL
  GROUP BY 1,2
),
tot AS (
  SELECT
    COALESCE(ing.almacen_id,egr.almacen_id,ap.almacen_id,an.almacen_id,ti.almacen_id,to2.almacen_id) AS almacen_id,
    COALESCE(ing.material_id,egr.material_id,ap.material_id,an.material_id,ti.material_id,to2.material_id) AS material_id,
    COALESCE(ing.qty,0) - COALESCE(egr.qty,0) + COALESCE(ap.qty,0) - COALESCE(an.qty,0)
    + COALESCE(ti.qty,0) - COALESCE(to2.qty,0) AS cantidad
  FROM ing
  FULL JOIN egr  USING (almacen_id, material_id)
  FULL JOIN ap   USING (almacen_id, material_id)
  FULL JOIN an   USING (almacen_id, material_id)
  FULL JOIN ti   USING (almacen_id, material_id)
  FULL JOIN to2  USING (almacen_id, material_id)
)
INSERT INTO public.stock_almacen(almacen_id, material_id, cantidad)
SELECT almacen_id, material_id, cantidad
FROM tot
WHERE cantidad > 0;

COMMIT;
