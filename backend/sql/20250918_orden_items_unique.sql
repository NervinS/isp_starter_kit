-- 20250918_orden_items_unique.sql
-- Crea un índice único para el upsert de líneas de orden.
-- Se adapta a esquemas que usen 'orden_items' o 'orden_materiales'.

DO $$
DECLARE
  has_orden_items boolean := EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'orden_items'
  );
  has_orden_materiales boolean := EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'orden_materiales'
  );
BEGIN
  IF has_orden_items THEN
    -- Nombre de índice consistente
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname='public' AND indexname='ux_orden_items_orden_mat'
    ) THEN
      EXECUTE 'CREATE UNIQUE INDEX ux_orden_items_orden_mat
               ON orden_items(orden_id, material_id)';
    END IF;

  ELSIF has_orden_materiales THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname='public' AND indexname='ux_orden_materiales_orden_mat'
    ) THEN
      EXECUTE 'CREATE UNIQUE INDEX ux_orden_materiales_orden_mat
               ON orden_materiales(orden_id, material_id)';
    END IF;

  ELSE
    -- Ninguna de las dos tablas existe: no hacemos nada
    RAISE NOTICE 'No existen ni orden_items ni orden_materiales. Saltando índice único.';
  END IF;
END $$;
