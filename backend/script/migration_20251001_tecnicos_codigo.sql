-- Asegura columna 'codigo' en tecnicos + única + backfill seguro
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='tecnicos' AND column_name='codigo'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN codigo TEXT;
  END IF;
END$$;

-- Backfill: asigna TEC-<8uuid> donde esté nulo/vacío
UPDATE tecnicos
SET codigo = 'TEC-' || SUBSTRING(id::text, 1, 8)
WHERE (codigo IS NULL OR codigo = '');

-- Índice único si no existe (permite múltiples NULL si quedaron)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname='uq_tecnicos_codigo'
       AND conrelid='tecnicos'::regclass
  ) THEN
    ALTER TABLE tecnicos ADD CONSTRAINT uq_tecnicos_codigo UNIQUE (codigo);
  END IF;
END$$;
