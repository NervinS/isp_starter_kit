-- Asegura que movimientos.tipo acepte 'traslado' (idempotente)
DO $$
DECLARE
  has_ck BOOLEAN;
BEGIN
  -- ¿Existe alguna CHECK sobre tipo?
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'movimientos'::regclass
      AND contype = 'c'
      AND conname = 'movimientos_tipo_check'
  ) INTO has_ck;

  IF has_ck THEN
    -- Reemplaza la CHECK por una que incluya 'traslado'
    ALTER TABLE movimientos DROP CONSTRAINT movimientos_tipo_check;
  END IF;

  -- Crea (o recrea) la CHECK correcta
  ALTER TABLE movimientos
    ADD CONSTRAINT movimientos_tipo_check
    CHECK (tipo IN ('ingreso','egreso','ajuste','traslado'));
END$$;
