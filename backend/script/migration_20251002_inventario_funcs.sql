-- script/migration_20251002_inventario_funcs.sql
-- Normaliza funciones de inventario (idempotente):
-- - Si existe fn_mov_traslado con retorno ≠ uuid, la eliminamos.
-- - (Re)creamos fn_stock_apply (helper UPSERT de stock).
-- - (Re)creamos fn_mov_traslado con RETURN uuid y columnas explícitas.

-- 0) Si existe fn_mov_traslado con retorno distinto a uuid, dropearla
DO $$
DECLARE
  f_oid    oid;
  ret_type regtype;
BEGIN
  SELECT p.oid, pg_get_function_result(p.oid)::regtype
    INTO f_oid, ret_type
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_mov_traslado'
    AND pg_get_function_identity_arguments(p.oid) = 'uuid, uuid, integer, numeric, text'
  LIMIT 1;

  IF f_oid IS NOT NULL AND ret_type <> 'uuid'::regtype THEN
    EXECUTE 'DROP FUNCTION public.fn_mov_traslado(uuid, uuid, integer, numeric, text)';
  END IF;
END$$;

-- 1) Helper de stock con UPSERT seguro
CREATE OR REPLACE FUNCTION public.fn_stock_apply(
  _almacen  uuid,
  _material integer,
  _delta    numeric
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  LOOP
    UPDATE public.stock_almacen
       SET cantidad   = GREATEST(0, cantidad + _delta),
           updated_at = now()
     WHERE almacen_id = _almacen
       AND material_id = _material;

    IF FOUND THEN
      RETURN;
    END IF;

    BEGIN
      INSERT INTO public.stock_almacen (almacen_id, material_id, cantidad, updated_at)
      VALUES (_almacen, _material, GREATEST(0, _delta), now());
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- otro proceso insertó en paralelo, reintentar
    END;
  END LOOP;
END;
$$;

-- 2) Traslado con RETURN uuid + columnas explícitas
CREATE OR REPLACE FUNCTION public.fn_mov_traslado(
  _from     uuid,
  _to       uuid,
  _material integer,
  _cantidad numeric,
  _nota     text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  _id uuid;
BEGIN
  -- Aplica stock en ambos almacenes
  PERFORM public.fn_stock_apply(_from, _material, -_cantidad);
  PERFORM public.fn_stock_apply(_to,   _material,  _cantidad);

  -- Inserta movimiento con columnas explícitas
  INSERT INTO public.movimientos (
    tipo, material_id, cantidad, fecha,
    from_almacen_id, to_almacen_id, nota
  )
  VALUES (
    'traslado', _material, _cantidad, now(),
    _from, _to, _nota
  )
  RETURNING id INTO _id;

  RETURN _id;
END;
$$;
