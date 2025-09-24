BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='orden_cierres_idem'
      AND column_name='idempotency_key'
  ) THEN
    ALTER TABLE public.orden_cierres_idem
      ADD COLUMN idempotency_key VARCHAR(128);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_oci_key
  ON public.orden_cierres_idem (idempotency_key);

ALTER TABLE public.ordenes
  ADD COLUMN IF NOT EXISTS agenda_fecha DATE,
  ADD COLUMN IF NOT EXISTS agenda_turno VARCHAR(16),
  ADD COLUMN IF NOT EXISTS tecnico_id UUID;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='tecnicos'
  ) THEN
    BEGIN
      ALTER TABLE public.ordenes
        ADD CONSTRAINT fk_ordenes_tecnico
        FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id)
        ON UPDATE CASCADE ON DELETE SET NULL;
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END IF;
END$$;

COMMIT;
