-- script/migration_20251002_inventario_funcs_force.sql
-- Fuerza la actualización de funciones de inventario.
-- - Asegura updated_at en stock_almacen
-- - DROP seguro de fn_mov_traslado (si existe con la firma esperada)
-- - (Re)crea fn_stock_apply (idempotente)
-- - (Re)crea fn_mov_traslado que RETORNA uuid y usa lista de columnas

-- 1) Asegura updated_at en stock_almacen
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='stock_almacen' AND column_name='updated_at'
  ) THEN
    ALTER TABLE public.stock_almacen ADD COLUMN updated_at timestamptz;
  END IF;

  ALTER TABLE public.stock_almacen
    ALTER COLUMN updated_at SET DEFAULT now();
END$$;

-- 2) Asegura DROP de cualquier versión previa de fn_mov_traslado
--    (mismo nombre y misma firma, sin importar tipo de retorno previo)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_mov_traslado'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid, uuid, integer, numeric, text'
  ) THEN
    EXECUTE 'DROP FUNCTION public.fn_mov_traslado(uuid, uuid, integer, numeric, text)';
  END IF;
END$$;

-- (Opcional) también podemos limpiar la helper si quieres reemplazarla siempre
-- DROP FUNCTION IF EXISTS public.fn_stock_apply(uuid, integer, numeric);

-- 3) (Re)crea helper de stock con UPSERT seguro
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

-- 4) (Re)crea traslado con RETURN uuid + columnas explícitas
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

  -- Inserta movimiento con lista de columnas explícita
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
