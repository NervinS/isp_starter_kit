-- 20251003_0600_add_ts_to_orden_equipos.sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name='orden_equipos' AND column_name='created_at'
  ) THEN
    ALTER TABLE orden_equipos
      ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END$$;

-- trigger para updated_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger WHERE tgname='trg_orden_equipos_set_updated_at'
  ) THEN
    CREATE OR REPLACE FUNCTION orden_equipos_set_updated_at()
    RETURNS trigger AS $f$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END;$f$ LANGUAGE plpgsql;

    CREATE TRIGGER trg_orden_equipos_set_updated_at
    BEFORE UPDATE ON orden_equipos
    FOR EACH ROW EXECUTE FUNCTION orden_equipos_set_updated_at();
  END IF;
END$$;
