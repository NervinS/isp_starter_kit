-- 20251003_0300_add_created_updated_to_ordenes.sql
DO $$
BEGIN
  -- created_at
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='ordenes' AND column_name='created_at'
  ) THEN
    ALTER TABLE ordenes ADD COLUMN created_at timestamptz;
    -- backfill: usa agendada_at si existe, si no now()
    UPDATE ordenes
      SET created_at = COALESCE(agendada_at, now())
      WHERE created_at IS NULL;
    ALTER TABLE ordenes ALTER COLUMN created_at SET NOT NULL;
    ALTER TABLE ordenes ALTER COLUMN created_at SET DEFAULT now();
    CREATE INDEX IF NOT EXISTS ix_ordenes_created_at ON ordenes(created_at);
  END IF;

  -- updated_at
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='ordenes' AND column_name='updated_at'
  ) THEN
    ALTER TABLE ordenes ADD COLUMN updated_at timestamptz;
    -- backfill: si hay cerrada_at/agendada_at úsalo como proxy, si no now()
    UPDATE ordenes
      SET updated_at = COALESCE(cerrada_at, agendada_at, now())
      WHERE updated_at IS NULL;
    ALTER TABLE ordenes ALTER COLUMN updated_at SET NOT NULL;
    ALTER TABLE ordenes ALTER COLUMN updated_at SET DEFAULT now();
    CREATE INDEX IF NOT EXISTS ix_ordenes_updated_at ON ordenes(updated_at);
  END IF;
END$$;

-- Trigger para auto-actualizar updated_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='ordenes_set_updated_at'
  ) THEN
    CREATE OR REPLACE FUNCTION ordenes_set_updated_at()
    RETURNS trigger AS $TG$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END;
    $TG$ LANGUAGE plpgsql;
  END IF;

  -- Crea el trigger si no existe
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname='trg_ordenes_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_ordenes_set_updated_at
    BEFORE UPDATE ON ordenes
    FOR EACH ROW
    EXECUTE PROCEDURE ordenes_set_updated_at();
  END IF;
END$$;
