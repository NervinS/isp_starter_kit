-- script/migration_20251002_kardex_view.sql
-- Idempotente: si la vista existe con otra firma, la dropeamos y la recreamos.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM   pg_views
    WHERE  schemaname = 'public'
    AND    viewname   = 'inventario_kardex_view'
  ) THEN
    EXECUTE 'DROP VIEW public.inventario_kardex_view';
  END IF;
END
$$;

-- Versión simple/estable de la vista (ajústala si luego quieres más columnas)
CREATE VIEW public.inventario_kardex_view AS
SELECT
  m.id,
  m.fecha,
  m.material_id,
  m.tipo,
  m.from_almacen_id,
  m.to_almacen_id,
  m.cantidad,
  m.nota
FROM public.movimientos m;
