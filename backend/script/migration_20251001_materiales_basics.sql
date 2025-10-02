-- Normaliza columnas clave en materiales (idempotente y seguro)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='materiales' AND column_name='unidad'
  ) THEN
    ALTER TABLE materiales ADD COLUMN unidad TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='materiales' AND column_name='activo'
  ) THEN
    ALTER TABLE materiales ADD COLUMN activo BOOLEAN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='materiales' AND column_name='created_at'
  ) THEN
    ALTER TABLE materiales ADD COLUMN created_at TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='materiales' AND column_name='updated_at'
  ) THEN
    ALTER TABLE materiales ADD COLUMN updated_at TIMESTAMPTZ;
  END IF;
END$$;

-- Defaults y saneo
ALTER TABLE materiales ALTER COLUMN activo SET DEFAULT TRUE;
UPDATE materiales SET activo=TRUE WHERE activo IS NULL;

ALTER TABLE materiales ALTER COLUMN created_at SET DEFAULT now();
UPDATE materiales SET created_at=now() WHERE created_at IS NULL;

ALTER TABLE materiales ALTER COLUMN updated_at SET DEFAULT now();
UPDATE materiales SET updated_at=now() WHERE updated_at IS NULL;

-- (Opcional) endurecer NOT NULL si no rompe nada:
-- ALTER TABLE materiales ALTER COLUMN unidad SET NOT NULL;
-- ALTER TABLE materiales ALTER COLUMN activo SET NOT NULL;
-- ALTER TABLE materiales ALTER COLUMN created_at SET NOT NULL;
-- ALTER TABLE materiales ALTER COLUMN updated_at SET NOT NULL;

-- Índice/constraint único por código si quieres ON CONFLICT (codigo)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='uq_materiales_codigo'
      AND conrelid='materiales'::regclass
  ) THEN
    ALTER TABLE materiales ADD CONSTRAINT uq_materiales_codigo UNIQUE (codigo);
  END IF;
END$$;
