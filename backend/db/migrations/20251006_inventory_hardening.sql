BEGIN;

-- 1) Normalización de valores en 'tipo'
UPDATE public.movimientos
SET tipo = CASE
  WHEN lower(tipo) = 'transferencia' THEN 'traslado'
  ELSE lower(tipo)
END
WHERE tipo IS NOT NULL
  AND (tipo <> lower(tipo) OR lower(tipo) = 'transferencia');

-- 2) CHECK (si no existe, créalo)
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'ck_movimientos_tipo'
        AND conrelid = 'public.movimientos'::regclass
  ) THEN
    ALTER TABLE public.movimientos
      ADD CONSTRAINT ck_movimientos_tipo
      CHECK (tipo IN ('ingreso','egreso','ajuste','traslado'));
  END IF;
END$$;

-- 3) Índices
CREATE INDEX IF NOT EXISTS idx_movs_tipo_mat_fecha
  ON public.movimientos (tipo, material_id, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_movs_to_mat_fecha
  ON public.movimientos (to_almacen_id, material_id, fecha DESC)
  WHERE to_almacen_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_movs_from_mat_fecha
  ON public.movimientos (from_almacen_id, material_id, fecha DESC)
  WHERE from_almacen_id IS NOT NULL;

-- 4) Idempotency
ALTER TABLE public.movimientos
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS ux_movs_idemkey
  ON public.movimientos (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMIT;
