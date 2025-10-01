-- 2025-10-01: columna motivo_anulacion en ordenes (idempotente)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema='public'
       AND table_name='ordenes'
       AND column_name='motivo_anulacion'
  ) THEN
    ALTER TABLE public.ordenes
      ADD COLUMN motivo_anulacion text NULL;
  END IF;
END$$;

-- índice pequeño para reportes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname='ix_ordenes_motivo_anulacion'
  ) THEN
    CREATE INDEX ix_ordenes_motivo_anulacion ON public.ordenes (estado) WHERE motivo_anulacion IS NOT NULL;
  END IF;
END$$;
