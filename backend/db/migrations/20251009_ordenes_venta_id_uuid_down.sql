-- 20251009_ordenes_venta_id_uuid_down.sql
-- Revierte a bigint y quita FK/índices creados en el "up".

BEGIN;

-- 1) Quita FK e índices
ALTER TABLE public.ordenes
  DROP CONSTRAINT IF EXISTS ordenes_venta_id_fkey;

DROP INDEX IF EXISTS ux_ordenes_ins_unica_por_venta;
DROP INDEX IF EXISTS idx_ordenes_venta_id;

-- 2) Vuelve a BIGINT (forzando NULL para evitar errores de cast)
ALTER TABLE public.ordenes
  ALTER COLUMN venta_id TYPE bigint USING NULL::bigint;

COMMIT;
