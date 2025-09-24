-- sql/006_inv_tecnico.sql
-- Inventario por técnico/material
-- Idempotente: puede correrse múltiples veces sin romper nada.

-- 0) prereqs
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) tabla base
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inv_tecnico'
  ) THEN
    CREATE TABLE inv_tecnico (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      tecnico_id  UUID        NOT NULL,
      material_id INTEGER     NOT NULL,
      cantidad    INTEGER     NOT NULL DEFAULT 0 CHECK (cantidad >= 0),
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ
    );
  END IF;
END$$;

-- 2) columnas requeridas si la tabla existía sin ellas
ALTER TABLE inv_tecnico
  ADD COLUMN IF NOT EXISTS id UUID,
  ADD COLUMN IF NOT EXISTS tecnico_id UUID,
  ADD COLUMN IF NOT EXISTS material_id INTEGER,
  ADD COLUMN IF NOT EXISTS cantidad INTEGER,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- 2.1) llaves y defaults por si faltaban
DO $$
BEGIN
  -- PK
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'inv_tecnico'::regclass AND contype='p'
  ) THEN
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT pk_inv_tecnico PRIMARY KEY (id);
  END IF;

  -- default id
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_name='inv_tecnico' AND column_name='id' AND column_default IS NOT NULL
  ) THEN
    ALTER TABLE inv_tecnico
      ALTER COLUMN id SET DEFAULT gen_random_uuid();
  END IF;

  -- default cantidad
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_name='inv_tecnico' AND column_name='cantidad' AND column_default IS NOT NULL
  ) THEN
    ALTER TABLE inv_tecnico
      ALTER COLUMN cantidad SET DEFAULT 0;
  END IF;

  -- check cantidad >= 0 (solo si no existe alguno similar)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='inv_tecnico'::regclass AND contype='c' AND conname='chk_inv_tecnico_cantidad_nn'
  ) THEN
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT chk_inv_tecnico_cantidad_nn CHECK (cantidad >= 0);
  END IF;

  -- default created_at
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_name='inv_tecnico' AND column_name='created_at' AND column_default IS NOT NULL
  ) THEN
    ALTER TABLE inv_tecnico
      ALTER COLUMN created_at SET DEFAULT now();
  END IF;
END$$;

-- 3) índice único para upsert (tecnico_id, material_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='ux_inv_tecnico_tecmat'
  ) THEN
    CREATE UNIQUE INDEX ux_inv_tecnico_tecmat
      ON inv_tecnico (tecnico_id, material_id);
  END IF;
END$$;

-- 4) FKs opcionales (solo si existen tablas destino)
--    Ajusta los nombres si tu dominio usa otra convención.
DO $$
DECLARE
  has_tecnicos  boolean;
  has_materiales boolean;
BEGIN
  SELECT EXISTS(
           SELECT 1 FROM information_schema.tables
           WHERE table_schema='public' AND table_name='tecnicos'
         ) INTO has_tecnicos;

  SELECT EXISTS(
           SELECT 1 FROM information_schema.tables
           WHERE table_schema='public' AND table_name='materiales'
         ) INTO has_materiales;

  IF has_tecnicos AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='inv_tecnico'::regclass AND conname='fk_inv_tecnico_tecnico'
  ) THEN
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT fk_inv_tecnico_tecnico
      FOREIGN KEY (tecnico_id) REFERENCES tecnicos(id) ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;

  IF has_materiales AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='inv_tecnico'::regclass AND conname='fk_inv_tecnico_material'
  ) THEN
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT fk_inv_tecnico_material
      FOREIGN KEY (material_id) REFERENCES materiales(id) ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;
END$$;

-- 5) trigger updated_at (before insert/update)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname='inv_tecnico_set_updated_at'
  ) THEN
    CREATE OR REPLACE FUNCTION inv_tecnico_set_updated_at()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $fn$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END
    $fn$;
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inv_tecnico'
  ) THEN
    -- recreate trigger safely
    IF EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid='inv_tecnico'::regclass AND tgname='tr_inv_tecnico_updated_at'
    ) THEN
      DROP TRIGGER tr_inv_tecnico_updated_at ON inv_tecnico;
    END IF;

    CREATE TRIGGER tr_inv_tecnico_updated_at
      BEFORE INSERT OR UPDATE ON inv_tecnico
      FOR EACH ROW
      EXECUTE FUNCTION inv_tecnico_set_updated_at();
  END IF;
END$$;
