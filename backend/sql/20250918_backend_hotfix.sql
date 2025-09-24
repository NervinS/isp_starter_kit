-- sql/20250918_backend_hotfix.sql
-- Alias / compat: algunas consultas esperan ordenes.usuario_id como sinónimo de tecnico_id
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ordenes' AND column_name='usuario_id'
  ) THEN
    ALTER TABLE ordenes ADD COLUMN usuario_id uuid NULL;
  END IF;
END$$;

-- Backfill inicial
UPDATE ordenes
SET usuario_id = COALESCE(usuario_id, tecnico_id)
WHERE usuario_id IS NULL AND tecnico_id IS NOT NULL;

-- Índice
CREATE INDEX IF NOT EXISTS ix_ordenes_usuario ON ordenes(usuario_id);

-- Trigger de sincronización (tecnico_id <-> usuario_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sync_usuario_tecnico'
  ) THEN
    CREATE OR REPLACE FUNCTION fn_sync_usuario_tecnico() RETURNS TRIGGER AS $f$
    BEGIN
      -- Si cambia tecnico_id y no se tocó usuario_id, sincroniza
      IF NEW.tecnico_id IS DISTINCT FROM OLD.tecnico_id
         AND (TG_OP = 'INSERT' OR NEW.usuario_id IS NOT DISTINCT FROM OLD.usuario_id) THEN
        NEW.usuario_id := NEW.tecnico_id;
      END IF;

      -- Si cambia usuario_id y no se tocó tecnico_id, sincroniza
      IF NEW.usuario_id IS DISTINCT FROM OLD.usuario_id
         AND (TG_OP = 'INSERT' OR NEW.tecnico_id IS NOT DISTINCT FROM OLD.tecnico_id) THEN
        NEW.tecnico_id := NEW.usuario_id;
      END IF;

      RETURN NEW;
    END;
    $f$ LANGUAGE plpgsql;

    CREATE TRIGGER trg_sync_usuario_tecnico
    BEFORE INSERT OR UPDATE ON ordenes
    FOR EACH ROW EXECUTE FUNCTION fn_sync_usuario_tecnico();
  END IF;
END$$;
