DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public' AND indexname='ux_orden_materiales_orden_mat'
  ) THEN
    CREATE UNIQUE INDEX ux_orden_materiales_orden_mat
      ON orden_materiales(orden_id, material_id);
  END IF;
END $$;
