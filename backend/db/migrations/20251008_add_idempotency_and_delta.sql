-- 20251008_add_idempotency_and_delta.sql

BEGIN;

-- 1) Idempotencia -----------------------------------------------------------
ALTER TABLE public.movimientos
  ADD COLUMN IF NOT EXISTS idempotency_key text;

-- Usa UNIQUE (no parcial). En PG, UNIQUE permite múltiples NULL.
ALTER TABLE public.movimientos
  DROP CONSTRAINT IF EXISTS uq_movimientos_idempotency_key;
ALTER TABLE public.movimientos
  ADD CONSTRAINT uq_movimientos_idempotency_key UNIQUE (idempotency_key);

-- 2) Delta + trigger + check -----------------------------------------------
ALTER TABLE public.movimientos
  ADD COLUMN IF NOT EXISTS delta numeric(12,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.movimientos_set_delta()
RETURNS trigger AS $$
BEGIN
  -- Normaliza delta segun tipo real (enum movimiento_tipo):
  --   ingreso        => +cantidad
  --   egreso         => -cantidad
  --   ajuste         =>  cantidad (ya con signo si viene negativo)
  --   transferencia  => 0
  --   traslado       => 0
  IF NEW.tipo = 'ingreso'::movimiento_tipo THEN
    NEW.delta := NEW.cantidad;
  ELSIF NEW.tipo = 'egreso'::movimiento_tipo THEN
    NEW.delta := -NEW.cantidad;
  ELSIF NEW.tipo = 'ajuste'::movimiento_tipo THEN
    NEW.delta := NEW.cantidad;
  ELSIF NEW.tipo IN ('transferencia'::movimiento_tipo, 'traslado'::movimiento_tipo) THEN
    NEW.delta := 0;
  ELSE
    NEW.delta := 0;
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_movimientos_set_delta ON public.movimientos;
CREATE TRIGGER trg_movimientos_set_delta
BEFORE INSERT OR UPDATE OF tipo, cantidad
ON public.movimientos
FOR EACH ROW
EXECUTE FUNCTION public.movimientos_set_delta();

ALTER TABLE public.movimientos
  DROP CONSTRAINT IF EXISTS ck_movimientos_delta_consistente;

ALTER TABLE public.movimientos
  ADD CONSTRAINT ck_movimientos_delta_consistente
  CHECK (
    (tipo = 'ingreso'::movimiento_tipo       AND delta =  cantidad) OR
    (tipo = 'egreso'::movimiento_tipo        AND delta = -cantidad) OR
    (tipo = 'ajuste'::movimiento_tipo        AND delta =  cantidad) OR
    (tipo IN ('transferencia'::movimiento_tipo, 'traslado'::movimiento_tipo) AND delta = 0)
  );

-- 3) Backfill seguro (idempotente) -----------------------------------------
-- Ajusta delta solo cuando aún esté en 0
UPDATE public.movimientos
SET delta = cantidad
WHERE delta = 0 AND tipo = 'ingreso'::movimiento_tipo;

UPDATE public.movimientos
SET delta = -cantidad
WHERE delta = 0 AND tipo = 'egreso'::movimiento_tipo;

UPDATE public.movimientos
SET delta = cantidad
WHERE delta = 0 AND tipo = 'ajuste'::movimiento_tipo;

UPDATE public.movimientos
SET delta = 0
WHERE delta = 0 AND tipo IN ('transferencia'::movimiento_tipo, 'traslado'::movimiento_tipo);

COMMIT;
