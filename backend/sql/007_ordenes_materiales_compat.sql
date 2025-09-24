-- sql/007_ordenes_materiales_compat.sql
-- Crea un alias estable "ordenes_materiales" a la tabla real de líneas (vista)
-- para que los scripts funcionen en ambientes con nombres diferentes.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  t_exists text;
BEGIN
  SELECT CASE
    WHEN to_regclass('public.ordenes_materiales') IS NOT NULL THEN 'ordenes_materiales'
    WHEN to_regclass('public.orden_materiales')  IS NOT NULL THEN 'orden_materiales'
    WHEN to_regclass('public.orden_material')    IS NOT NULL THEN 'orden_material'
    ELSE NULL
  END INTO t_exists;

  IF t_exists IS NULL THEN
    RAISE NOTICE 'No hay tabla compatible para alias ordenes_materiales';
    RETURN;
  END IF;

  IF t_exists = 'ordenes_materiales' THEN
    RAISE NOTICE 'Alias ordenes_materiales ya existe (ordenes_materiales), no se toca.';
    RETURN;
  END IF;

  EXECUTE format('CREATE OR REPLACE VIEW ordenes_materiales AS SELECT * FROM %I', t_exists);
  RAISE NOTICE 'Alias ordenes_materiales -> % creado como VIEW.', t_exists;
END $$;
