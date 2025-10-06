-- script/fix_kardex.sql
SET client_min_messages TO WARNING;
SET search_path TO public;

-- Limpia overrides locales
DROP RULE IF EXISTS kardex_insert ON public.kardex;
DROP TRIGGER IF EXISTS trg_movs_sync_stock ON public.movimientos;
DROP FUNCTION IF EXISTS public.trg_sync_stock_movimientos() CASCADE;
DROP FUNCTION IF EXISTS public.sync_stock_desde_kardex(uuid, int) CASCADE;

-- Re-crea vista kardex "oficial/simple"
DROP VIEW IF EXISTS public.kardex;

CREATE VIEW public.kardex AS
SELECT
  m.id,
  m.tipo,
  m.almacen_origen_id,
  m.almacen_destino_id,
  COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
  m.material_id,
  CASE
    WHEN m.tipo = 'transferencia' AND m.almacen_destino_id IS NOT NULL THEN 'ingreso'
    WHEN m.tipo = 'transferencia' AND m.almacen_origen_id  IS NOT NULL THEN 'egreso'
    ELSE m.tipo
  END AS etiqueta,
  CASE
    WHEN m.tipo IN ('ingreso','ajuste') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
    WHEN m.tipo = 'egreso'               AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
    WHEN m.tipo = 'transferencia'        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
    WHEN m.tipo = 'transferencia'        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
    ELSE 0
  END AS delta,
  m.cantidad,
  m.created_at
FROM public.movimientos m;

-- Índices útiles
CREATE INDEX IF NOT EXISTS ix_movs_dest_mat_created
  ON public.movimientos (almacen_destino_id, material_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_movs_orig_mat_created
  ON public.movimientos (almacen_origen_id,  material_id, created_at DESC);
