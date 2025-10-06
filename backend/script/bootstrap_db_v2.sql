-- backend/script/bootstrap_db_v2.sql
-- Idempotente: constraint único limpio en orden_materiales + índices útiles.

SET client_min_messages TO WARNING;
SET search_path TO public;

-- =========================
-- Constraint único limpio en orden_materiales
-- =========================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_orden_materiales_orden_id_material_id') THEN
    ALTER TABLE public.orden_materiales DROP CONSTRAINT uq_orden_materiales_orden_id_material_id;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ux_orden_materiales_orden_id_material_id') THEN
    DROP INDEX public.ux_orden_materiales_orden_id_material_id;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid='public.orden_materiales'::regclass
      AND conname='uq_orden_materiales_orden_material'
  ) THEN
    ALTER TABLE public.orden_materiales
      ADD CONSTRAINT uq_orden_materiales_orden_material UNIQUE (orden_id, material_id);
  END IF;
END$$;

-- =========================
-- Índices para consultas por almacén/material y fecha
-- =========================
CREATE INDEX IF NOT EXISTS ix_movs_dest_mat_created
  ON public.movimientos (almacen_destino_id, material_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_movs_orig_mat_created
  ON public.movimientos (almacen_origen_id,  material_id, created_at DESC);
