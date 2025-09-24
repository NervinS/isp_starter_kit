-- Mueve líneas de duplicados al registro "más nuevo" (mayor created_at)
WITH ranked AS (
  SELECT
    id,
    codigo,
    created_at,
    first_value(id) OVER (PARTITION BY codigo ORDER BY created_at DESC) AS keep_id,
    row_number()    OVER (PARTITION BY codigo ORDER BY created_at DESC) AS rn
  FROM ordenes
),
moved AS (
  UPDATE orden_materiales om
  SET orden_id = r.keep_id
  FROM ranked r
  WHERE om.orden_id = r.id
    AND r.rn > 1
  RETURNING 1
)
DELETE FROM ordenes o
USING ranked r
WHERE o.id = r.id
  AND r.rn > 1;

-- Índice único por código
CREATE UNIQUE INDEX IF NOT EXISTS ux_ordenes_codigo ON ordenes(codigo);
