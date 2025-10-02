-- Asegura created_at/updated_at en stock_almacen (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='stock_almacen' AND column_name='created_at'
  ) THEN
    ALTER TABLE stock_almacen ADD COLUMN created_at timestamptz;
    UPDATE stock_almacen SET created_at = now();
    ALTER TABLE stock_almacen ALTER COLUMN created_at SET DEFAULT now();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='stock_almacen' AND column_name='updated_at'
  ) THEN
    ALTER TABLE stock_almacen ADD COLUMN updated_at timestamptz;
    UPDATE stock_almacen SET updated_at = now();
    ALTER TABLE stock_almacen ALTER COLUMN updated_at SET DEFAULT now();
  END IF;
END$$;
