-- === Sincronía stock_almacen -> inv_tecnico (solo almacenes tipo 'tecnico') ===
-- Idempotente.

-- 0) Garantizar índice único (o al menos único lógico) en inv_tecnico(tecnico_id, material_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ux_inv_tecnico_tecmat'
  ) THEN
    CREATE UNIQUE INDEX ux_inv_tecnico_tecmat
      ON inv_tecnico (tecnico_id, material_id);
  END IF;
END$$;

-- 1) Función de sincronización
CREATE OR REPLACE FUNCTION sync_inv_tecnico_from_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_almacen uuid;
  v_tecnico uuid;
  v_material integer;
  v_cantidad numeric(18,6);
BEGIN
  -- Determinar almacén/material/cantidad según operación
  IF TG_OP = 'DELETE' THEN
    v_almacen  := OLD.almacen_id;
    v_material := OLD.material_id;
    v_cantidad := 0;  -- si se borra el renglón, inv_tecnico queda en 0
  ELSE
    v_almacen  := NEW.almacen_id;
    v_material := NEW.material_id;
    v_cantidad := COALESCE(NEW.cantidad, 0);
  END IF;

  -- Buscar técnico del almacén
  SELECT tecnico_id INTO v_tecnico
  FROM almacenes
  WHERE id = v_almacen
    AND tipo = 'tecnico';

  -- Si no es almacén técnico (o no tiene tecnico_id), no sincroniza
  IF v_tecnico IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Upsert espejo exacto en inv_tecnico
  INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
  VALUES (v_tecnico, v_material, v_cantidad)
  ON CONFLICT (tecnico_id, material_id)
  DO UPDATE SET cantidad = EXCLUDED.cantidad;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- 2) Trigger sobre stock_almacen
DROP TRIGGER IF EXISTS trg_sync_inv_tecnico ON stock_almacen;
CREATE TRIGGER trg_sync_inv_tecnico
AFTER INSERT OR UPDATE OR DELETE
ON stock_almacen
FOR EACH ROW
EXECUTE FUNCTION sync_inv_tecnico_from_stock();
