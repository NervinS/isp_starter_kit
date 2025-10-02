-- Idempotente: asegura updated_at en stock_almacen, re-crea fn_stock_apply,
-- y re-crea fn_mov_traslado con DROP condicional si el tipo de retorno difiere.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='stock_almacen' AND column_name='updated_at'
  ) THEN
    ALTER TABLE stock_almacen ADD COLUMN updated_at timestamptz;
    UPDATE stock_almacen SET updated_at = now();
    ALTER TABLE stock_almacen ALTER COLUMN updated_at SET DEFAULT now();
  END IF;
END$$;

-- Asegura función de aplicación de delta sobre stock (idempotente)
CREATE OR REPLACE FUNCTION fn_stock_apply(
  _almacen  uuid,
  _material integer,
  _delta    numeric
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  LOOP
    UPDATE stock_almacen
       SET cantidad   = GREATEST(0, cantidad + _delta),
           updated_at = now()
     WHERE almacen_id = _almacen
       AND material_id = _material;

    IF FOUND THEN
      RETURN;
    END IF;

    BEGIN
      INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
      VALUES (_almacen, _material, GREATEST(0, _delta));
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- Otro proceso insertó en paralelo; reintentar el UPDATE
    END;
  END LOOP;
END;
$$;

-- Si existe fn_mov_traslado con la misma firma pero distinto tipo de retorno, dropearla
DO $$
DECLARE
  rettype text;
BEGIN
  SELECT pg_catalog.format_type(p.prorettype, NULL) AS rettype
    INTO rettype
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'fn_mov_traslado'
    AND n.nspname = 'public'
    AND pg_get_function_identity_arguments(p.oid) = 'uuid, uuid, integer, numeric, text'
  LIMIT 1;

  IF rettype IS NOT NULL AND rettype <> 'uuid' THEN
    EXECUTE 'DROP FUNCTION public.fn_mov_traslado(uuid, uuid, integer, numeric, text)';
  END IF;
END$$;

-- Crear/Reemplazar con el tipo correcto (uuid) y columnas explícitas
CREATE OR REPLACE FUNCTION fn_mov_traslado(
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
  -- Aplica stock
  PERFORM fn_stock_apply(_from, _material, -_cantidad);
  PERFORM fn_stock_apply(_to,   _material,  _cantidad);

  -- Inserta movimiento, con lista de columnas explícita para evitar desalineos
  INSERT INTO movimientos (
    tipo,        material_id, cantidad,  fecha,
    from_almacen_id, to_almacen_id, nota
  )
  VALUES (
    'traslado',  _material,   _cantidad, now(),
    _from,       _to,          _nota
  )
  RETURNING id INTO _id;

  RETURN _id;
END;
$$;
