-- Normaliza columnas clave en tecnicos (idempotente y seguro)
DO $$
BEGIN
  -- nombre
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='tecnicos' AND column_name='nombre'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN nombre TEXT;
  END IF;

  -- activo
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='tecnicos' AND column_name='activo'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN activo BOOLEAN;
  END IF;

  -- timestamps (opcionales; si ya existen no hace nada)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='tecnicos' AND column_name='created_at'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN created_at TIMESTAMPTZ;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='tecnicos' AND column_name='updated_at'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN updated_at TIMESTAMPTZ;
  END IF;
END$$;

-- Defaults y saneo
ALTER TABLE tecnicos ALTER COLUMN activo SET DEFAULT TRUE;
UPDATE tecnicos SET activo=TRUE WHERE activo IS NULL;

ALTER TABLE tecnicos ALTER COLUMN created_at SET DEFAULT now();
UPDATE tecnicos SET created_at=now() WHERE created_at IS NULL;

ALTER TABLE tecnicos ALTER COLUMN updated_at SET DEFAULT now();
UPDATE tecnicos SET updated_at=now() WHERE updated_at IS NULL;

-- (Opcional) endurecer NOT NULL si no rompe nada
-- ALTER TABLE tecnicos ALTER COLUMN nombre SET NOT NULL;
-- ALTER TABLE tecnicos ALTER COLUMN activo SET NOT NULL;
-- ALTER TABLE tecnicos ALTER COLUMN created_at SET NOT NULL;
-- ALTER TABLE tecnicos ALTER COLUMN updated_at SET NOT NULL;
