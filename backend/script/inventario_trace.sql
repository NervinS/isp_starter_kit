-- script/inventario_trace.sql
-- Traza de devoluciones/asignaciones por técnico + función que además registra la traza.

-- 1) Tabla de trazabilidad por técnico
CREATE TABLE IF NOT EXISTS inventario_tecnico_traza (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fecha        timestamptz NOT NULL DEFAULT now(),
  accion       text NOT NULL CHECK (accion IN ('devolucion','asignacion')),
  tecnico_id   int NOT NULL,
  material_id  int NOT NULL,
  cantidad     numeric NOT NULL CHECK (cantidad > 0),
  from_almacen uuid NULL,
  to_almacen   uuid NULL,
  nota         text NULL
);
CREATE INDEX IF NOT EXISTS idx_traza_fecha    ON inventario_tecnico_traza(fecha DESC);
CREATE INDEX IF NOT EXISTS idx_traza_tecnico  ON inventario_tecnico_traza(tecnico_id);
CREATE INDEX IF NOT EXISTS idx_traza_material ON inventario_tecnico_traza(material_id);

-- 2) Reemplaza inv_aplicar_movimiento para además insertar en inventario_tecnico_traza
CREATE OR REPLACE FUNCTION inv_aplicar_movimiento(
  p_tipo        text,
  p_material_id int,
  p_cantidad    numeric,
  p_from        uuid,
  p_to          uuid,
  p_tecnico_id  int,
  p_nota        text
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_central uuid;
  v_saldo   numeric;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'cantidad debe ser > 0';
  END IF;

  SELECT id INTO v_central FROM almacenes WHERE codigo='CENTRAL' LIMIT 1;
  IF v_central IS NULL THEN
    RAISE EXCEPTION 'No existe almacén CENTRAL';
  END IF;

  IF p_tipo = 'ingreso' THEN
    -- TEC -> CENTRAL
    INSERT INTO kardex(etiqueta, almacen_id, material_id, cantidad)
    VALUES ('ingreso', v_central, p_material_id, p_cantidad);

    INSERT INTO stock_almacen(almacen_id, material_id, cantidad)
    VALUES (v_central, p_material_id, p_cantidad)
    ON CONFLICT (almacen_id, material_id)
    DO UPDATE SET cantidad = stock_almacen.cantidad + EXCLUDED.cantidad;

    INSERT INTO inventario_tecnico_traza(
      accion, tecnico_id, material_id, cantidad, from_almacen, to_almacen, nota
    ) VALUES (
      'devolucion', COALESCE(p_tecnico_id,0), p_material_id, p_cantidad, p_from, v_central, p_nota
    );

    RETURN;

  ELSIF p_tipo = 'egreso' THEN
    -- CENTRAL -> TEC
    SELECT COALESCE(cantidad,0) INTO v_saldo
      FROM stock_almacen
     WHERE almacen_id=v_central AND material_id=p_material_id
     FOR UPDATE;
    IF v_saldo < p_cantidad THEN
      RAISE EXCEPTION 'saldo insuficiente' USING ERRCODE='40999';
    END IF;

    INSERT INTO kardex(etiqueta, almacen_id, material_id, cantidad)
    VALUES ('egreso', v_central, p_material_id, p_cantidad);

    UPDATE stock_almacen
       SET cantidad = cantidad - p_cantidad
     WHERE almacen_id=v_central AND material_id=p_material_id;

    INSERT INTO inventario_tecnico_traza(
      accion, tecnico_id, material_id, cantidad, from_almacen, to_almacen, nota
    ) VALUES (
      'asignacion', COALESCE(p_tecnico_id,0), p_material_id, p_cantidad, v_central, p_to, p_nota
    );

    RETURN;

  ELSE
    RAISE EXCEPTION 'movimiento no permitido (tipo %)', p_tipo USING ERRCODE='22P03';
  END IF;
END
$$;
