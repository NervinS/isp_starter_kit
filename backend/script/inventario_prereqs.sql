-- script/inventario_prereqs.sql
-- Idempotente. Se ajusta al esquema actual (kardex es una VISTA con RULES).
-- No toca la vista kardex; sólo asegura prerequisitos que usamos desde inv_aplicar_movimiento().

-- 1) Extensión pgcrypto (para gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2) Asegurar PK compuesta en stock_almacen(almacen_id, material_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema='public'
      AND table_name='stock_almacen'
      AND constraint_type='PRIMARY KEY'
  ) THEN
    ALTER TABLE stock_almacen
      ADD PRIMARY KEY (almacen_id, material_id);
  END IF;
END
$$;

-- 3) Asegurar existencia de un Almacén Central identificado por codigo='CENTRAL'
--    (No usamos columna "role", ya que tu esquema no la tiene)
DO $$
DECLARE v_exists int;
BEGIN
  SELECT 1 INTO v_exists FROM almacenes WHERE codigo='CENTRAL' LIMIT 1;
  IF v_exists IS NULL THEN
    -- Ajusta columnas si tu tabla almacenes difiere
    INSERT INTO almacenes(id, tipo, codigo, nombre, es_activo, created_at)
    VALUES (gen_random_uuid(), 'central', 'CENTRAL', 'Almacén Central', true, now());
  END IF;
END
$$;
