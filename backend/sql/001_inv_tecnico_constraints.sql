-- Asegura índice único (tecnico_id, material_id)
CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_tecnico_tecmat
  ON public.inv_tecnico (tecnico_id, material_id);

-- Asegura que cantidad no sea negativa (emulado con DO/IF NOT EXISTS)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_stock_cantidad_nonneg'
      AND conrelid = 'public.inv_tecnico'::regclass
  ) THEN
    ALTER TABLE public.inv_tecnico
      ADD CONSTRAINT chk_stock_cantidad_nonneg CHECK (cantidad >= 0);
  END IF;
END $$;
