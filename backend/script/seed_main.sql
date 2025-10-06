WITH central AS (
  SELECT id, codigo
  FROM public.almacenes
  WHERE codigo IN ('MAIN','CENTRAL','PRINCIPAL')
  ORDER BY CASE codigo WHEN 'MAIN' THEN 1 WHEN 'CENTRAL' THEN 2 ELSE 3 END
  LIMIT 1
),
saldos AS (
  SELECT mat.id AS material_id,
         COALESCE(SUM(
           CASE
             WHEN m.tipo IN ('ingreso','ajuste') AND m.almacen_destino_id = (SELECT id FROM central) THEN  m.cantidad
             WHEN m.tipo = 'egreso'               AND m.almacen_origen_id  = (SELECT id FROM central) THEN -m.cantidad
             WHEN m.tipo = 'transferencia'        AND m.almacen_destino_id = (SELECT id FROM central) THEN  m.cantidad
             WHEN m.tipo = 'transferencia'        AND m.almacen_origen_id  = (SELECT id FROM central) THEN -m.cantidad
             ELSE 0
           END
         ),0) AS s
  FROM public.materiales mat
  LEFT JOIN public.movimientos m
         ON m.material_id = mat.id
        AND (
             m.almacen_destino_id = (SELECT id FROM central)
          OR m.almacen_origen_id  = (SELECT id FROM central)
        )
  GROUP BY mat.id
),
to_ins AS (
  SELECT (SELECT id FROM central) AS cid,
         material_id,
         GREATEST(:'QTY'::int - s, 0) AS falta
  FROM saldos
  WHERE GREATEST(:'QTY'::int - s, 0) > 0
)
INSERT INTO public.movimientos (tipo, almacen_origen_id, almacen_destino_id, material_id, cantidad, nota)
SELECT 'ingreso', NULL, cid, material_id, falta, 'seed CENTRAL make'
FROM to_ins;
