-- script/inventario_apply.sql
-- Implementa inv_aplicar_movimiento() respetando tu política:
--   - SOLO TEC -> CENTRAL (devolución)  => tipo 'ingreso'
--   - SOLO CENTRAL -> TEC (asignación)  => tipo 'egreso'
-- Kardex en tu esquema es una VISTA con RULE:
--   INSERT INTO kardex(etiqueta, almacen_id, material_id, cantidad)
--   etiqueta='ingreso' -> ingreso al almacen_id
--   etiqueta='egreso'  -> egreso  desde almacen_id
-- Además de escribir en kardex, actualizamos stock_almacen del CENTRAL
-- para mantener saldos consistentes.

CREATE OR REPLACE FUNCTION inv_aplicar_movimiento(
  p_tipo        text,     -- 'ingreso' (TEC->Central)  | 'egreso' (Central->TEC)
  p_material_id int,
  p_cantidad    numeric,
  p_from        uuid,     -- opcional (informativo)
  p_to          uuid,     -- opcional (informativo)
  p_tecnico_id  int,      -- opcional (informativo)
  p_nota        text      -- opcional (informativo)
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_central uuid;
  v_saldo   numeric;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'cantidad debe ser > 0';
  END IF;

  -- Identificar CENTRAL por codigo para no depender de columnas inexistentes
  SELECT id INTO v_central FROM almacenes WHERE codigo='CENTRAL' LIMIT 1;
  IF v_central IS NULL THEN
    RAISE EXCEPTION 'No existe almacén CENTRAL';
  END IF;

  IF p_tipo = 'ingreso' THEN
    -- Devolución TEC -> CENTRAL
    -- 1) Kardex (vista): ingreso a CENTRAL
    INSERT INTO kardex(etiqueta, almacen_id, material_id, cantidad)
    VALUES ('ingreso', v_central, p_material_id, p_cantidad);

    -- 2) Stock del CENTRAL: suma
    INSERT INTO stock_almacen(almacen_id, material_id, cantidad)
    VALUES (v_central, p_material_id, p_cantidad)
    ON CONFLICT (almacen_id, material_id)
    DO UPDATE SET cantidad = stock_almacen.cantidad + EXCLUDED.cantidad;

    RETURN;

  ELSIF p_tipo = 'egreso' THEN
    -- Asignación CENTRAL -> TEC
    -- 1) Validación de saldo CENTRAL
    SELECT COALESCE(cantidad,0) INTO v_saldo
      FROM stock_almacen
     WHERE almacen_id=v_central AND material_id=p_material_id
     FOR UPDATE;
    IF v_saldo < p_cantidad THEN
      RAISE EXCEPTION 'saldo insuficiente' USING ERRCODE='40999';
    END IF;

    -- 2) Kardex (vista): egreso desde CENTRAL
    INSERT INTO kardex(etiqueta, almacen_id, material_id, cantidad)
    VALUES ('egreso', v_central, p_material_id, p_cantidad);

    -- 3) Stock del CENTRAL: descuenta
    UPDATE stock_almacen
       SET cantidad = cantidad - p_cantidad
     WHERE almacen_id=v_central AND material_id=p_material_id;

    RETURN;

  ELSE
    RAISE EXCEPTION 'movimiento no permitido (tipo %)', p_tipo USING ERRCODE='22P03';
  END IF;
END
$$;
