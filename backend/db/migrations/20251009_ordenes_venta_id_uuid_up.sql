-- 20251009_ordenes_venta_id_uuid_up.sql
-- Cambia ordenes.venta_id a UUID, crea índice y FK, y asegura
-- unicidad de una sola INS activa por venta.

BEGIN;

-- (Defensivo) Limpia artefactos peligrosos, si alguien los dejó
DROP CAST IF EXISTS (uuid AS bigint);
DROP FUNCTION IF EXISTS public.uuid_to_bigint(uuid);

-- 1) Cambia tipo (mantiene NULL como NULL)
ALTER TABLE public.ordenes
  ALTER COLUMN venta_id DROP DEFAULT,
  ALTER COLUMN venta_id TYPE uuid USING NULL::uuid;

-- 2) (OPCIONAL) Backfill si tienes cómo mapear órdenes → ventas
--    Deja comentado si no aplica. Ejemplo con form_data->>'venta_codigo':
-- WITH to_set AS (
--   SELECT o.id  AS orden_pk,
--          v.id  AS venta_uuid
--   FROM   public.ordenes o
--   JOIN   public.ventas v
--          ON (o.form_data->>'venta_codigo') = v.codigo
--   WHERE  o.venta_id IS NULL
-- )
-- UPDATE public.ordenes o
-- SET    venta_id = t.venta_uuid
-- FROM   to_set t
-- WHERE  o.id = t.orden_pk;

-- 3) Índice para búsquedas/joins por venta_id (idempotente)
CREATE INDEX IF NOT EXISTS idx_ordenes_venta_id
  ON public.ordenes(venta_id);

-- 4) FK a ventas(id) con ON DELETE SET NULL (forzado/idempotente)
ALTER TABLE public.ordenes
  DROP CONSTRAINT IF EXISTS ordenes_venta_id_fkey,
  ADD  CONSTRAINT ordenes_venta_id_fkey
  FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE SET NULL;

-- 5) Unicidad: una sola INS activa por venta
--    (estado <> 'anulada' permite crear nueva cuando se anula la previa)
CREATE UNIQUE INDEX IF NOT EXISTS ux_ordenes_ins_unica_por_venta
  ON public.ordenes (venta_id)
  WHERE tipo = 'INS' AND estado <> 'anulada';

COMMIT;
