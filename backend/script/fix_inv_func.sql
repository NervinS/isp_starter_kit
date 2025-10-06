-- script/fix_inv_func.sql
SET client_min_messages = WARNING;

CREATE OR REPLACE FUNCTION inv_aplicar_movimiento(
  p_tipo        text,
  p_material_id integer,
  p_cantidad    numeric,
  p_from        uuid,
  p_to          uuid,
  p_tecnico_id  integer,
  p_nota        text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_tipo text := lower(p_tipo);
BEGIN
  IF p_material_id IS NULL OR p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'parámetros inválidos (material_id %, cantidad %)', p_material_id, p_cantidad;
  END IF;

  -- ===== transferencia/traslado (egreso en ORIGEN + ingreso en DESTINO) =====
  IF v_tipo IN ('transferencia','traslado') THEN
    IF p_from IS NULL OR p_to IS NULL THEN
      RAISE EXCEPTION 'transferencia requiere p_from y p_to';
    END IF;

    -- egreso en origen
    INSERT INTO movimientos (tipo, material_id, almacen_origen_id, cantidad, tecnico_id, nota)
    VALUES ('egreso', p_material_id, p_from, p_cantidad, p_tecnico_id, p_nota);

    UPDATE stock_almacen
       SET cantidad = cantidad - p_cantidad
     WHERE almacen_id = p_from AND material_id = p_material_id;
    IF NOT FOUND THEN
      INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
      VALUES (p_from, p_material_id, 0);
      UPDATE stock_almacen
         SET cantidad = cantidad - p_cantidad
       WHERE almacen_id = p_from AND material_id = p_material_id;
    END IF;

    -- ingreso en destino
    INSERT INTO movimientos (tipo, material_id, almacen_destino_id, cantidad, tecnico_id, nota)
    VALUES ('ingreso', p_material_id, p_to, p_cantidad, p_tecnico_id, p_nota);

    INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
    VALUES (p_to, p_material_id, p_cantidad)
    ON CONFLICT (almacen_id, material_id)
    DO UPDATE SET cantidad = stock_almacen.cantidad + EXCLUDED.cantidad;

    RETURN;
  END IF;

  -- ===== ingreso =====
  IF v_tipo = 'ingreso' THEN
    IF p_to IS NULL THEN RAISE EXCEPTION 'ingreso requiere p_to'; END IF;
    INSERT INTO movimientos (tipo, material_id, almacen_destino_id, cantidad, tecnico_id, nota)
    VALUES ('ingreso', p_material_id, p_to, p_cantidad, p_tecnico_id, p_nota);

    INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
    VALUES (p_to, p_material_id, p_cantidad)
    ON CONFLICT (almacen_id, material_id)
    DO UPDATE SET cantidad = stock_almacen.cantidad + EXCLUDED.cantidad;
    RETURN;
  END IF;

  -- ===== egreso =====
  IF v_tipo = 'egreso' THEN
    IF p_from IS NULL THEN RAISE EXCEPTION 'egreso requiere p_from'; END IF;
    INSERT INTO movimientos (tipo, material_id, almacen_origen_id, cantidad, tecnico_id, nota)
    VALUES ('egreso', p_material_id, p_from, p_cantidad, p_tecnico_id, p_nota);

    UPDATE stock_almacen
       SET cantidad = cantidad - p_cantidad
     WHERE almacen_id = p_from AND material_id = p_material_id;
    IF NOT FOUND THEN
      INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
      VALUES (p_from, p_material_id, 0);
      UPDATE stock_almacen
         SET cantidad = cantidad - p_cantidad
       WHERE almacen_id = p_from AND material_id = p_material_id;
    END IF;
    RETURN;
  END IF;

  -- ===== ajuste (+ o -) =====
  IF v_tipo = 'ajuste' THEN
    IF p_to IS NOT NULL THEN
      INSERT INTO movimientos (tipo, material_id, almacen_destino_id, cantidad, tecnico_id, nota)
      VALUES ('ingreso', p_material_id, p_to, p_cantidad, p_tecnico_id, COALESCE(p_nota, 'ajuste +'));

      INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
      VALUES (p_to, p_material_id, p_cantidad)
      ON CONFLICT (almacen_id, material_id)
      DO UPDATE SET cantidad = stock_almacen.cantidad + EXCLUDED.cantidad;
      RETURN;

    ELSIF p_from IS NOT NULL THEN
      INSERT INTO movimientos (tipo, material_id, almacen_origen_id, cantidad, tecnico_id, nota)
      VALUES ('egreso', p_material_id, p_from, p_cantidad, p_tecnico_id, COALESCE(p_nota, 'ajuste -'));

      UPDATE stock_almacen
         SET cantidad = cantidad - p_cantidad
       WHERE almacen_id = p_from AND material_id = p_material_id;
      IF NOT FOUND THEN
        INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
        VALUES (p_from, p_material_id, 0);
        UPDATE stock_almacen
           SET cantidad = cantidad - p_cantidad
         WHERE almacen_id = p_from AND material_id = p_material_id;
      END IF;
      RETURN;

    ELSE
      RAISE EXCEPTION 'ajuste requiere p_to (suma) o p_from (resta)';
    END IF;
  END IF;

  RAISE EXCEPTION 'movimiento no permitido (tipo %)', p_tipo;
END;
$$;
