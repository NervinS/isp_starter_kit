-- 20251003_0500_fix_unique_idx_ins.sql
-- Objetivo: permitir múltiples INS históricas por venta, pero 1 sola INS ACTIVA.
-- Activa = estado IN ('creada','agendada','en_proceso')

DO $$
BEGIN
  -- Drop ambos índices previos si existen
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_orden_ins_activa') THEN
    DROP INDEX ux_orden_ins_activa;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_orden_unica_ins_venta_activa') THEN
    DROP INDEX ux_orden_unica_ins_venta_activa;
  END IF;

  -- Crear único correcto solo para estados activos
  CREATE UNIQUE INDEX ux_orden_unica_ins_venta_activa
    ON ordenes(venta_id)
    WHERE tipo = 'INS'
      AND estado IN ('creada','agendada','en_proceso');
END$$;
