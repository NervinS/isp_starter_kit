DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ordenes' AND column_name='motivo_reagenda_codigo'
  ) THEN
    ALTER TABLE ordenes ADD COLUMN motivo_reagenda_codigo text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ordenes' AND column_name='motivo_reagenda'
  ) THEN
    ALTER TABLE ordenes ADD COLUMN motivo_reagenda text;
  END IF;
END
$$;
