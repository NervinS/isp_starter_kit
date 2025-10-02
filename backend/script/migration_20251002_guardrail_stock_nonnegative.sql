-- Garantiza que no haya saldo negativo en stock_almacen
ALTER TABLE public.stock_almacen
  ADD CONSTRAINT stock_almacen_cantidad_nonneg
  CHECK (cantidad >= 0);

-- Rechaza egresos/traslados sin saldo suficiente
CREATE OR REPLACE FUNCTION public.fn_movimientos_guardrail_saldo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  _from uuid;
  _needed integer;
  _have integer;
BEGIN
  IF NEW.tipo IN ('egreso','transferencia') THEN
    _needed := NEW.cantidad;
    _from   := NEW.almacen_origen_id;

    IF _from IS NOT NULL THEN
      SELECT COALESCE(cantidad,0) INTO _have
      FROM public.stock_almacen
      WHERE almacen_id = _from AND material_id = NEW.material_id
      FOR UPDATE; -- bloquea fila para evitar carrera

      IF _have < _needed THEN
        RAISE EXCEPTION 'Saldo insuficiente en almacén % para material %, requerido %, actual %',
          _from, NEW.material_id, _needed, _have
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_movimientos_guardrail_saldo ON public.movimientos;
CREATE TRIGGER trg_movimientos_guardrail_saldo
BEFORE INSERT ON public.movimientos
FOR EACH ROW
EXECUTE FUNCTION public.fn_movimientos_guardrail_saldo();
