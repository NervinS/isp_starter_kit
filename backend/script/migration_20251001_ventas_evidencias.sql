-- 2025-10-01 migración Ventas: columnas de evidencias (idempotente)

-- Asegurar tabla ventas existe (por si entornos limpios)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='ventas'
  ) THEN
    RAISE EXCEPTION 'Tabla public.ventas no existe; ejecuta primero migration_20251001_ventas_ordenes.sql';
  END IF;
END$$;

-- Agregar columnas de evidencias si no existen
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS cedula_img_key  text,
  ADD COLUMN IF NOT EXISTS recibo_img_key  text,
  ADD COLUMN IF NOT EXISTS firma_img_key   text;

-- (Opcional) Vista rápida de cumplimiento de firma
CREATE OR REPLACE VIEW public.ventas_firma_pendiente AS
SELECT codigo, estado, firma_img_key IS NULL AS requiere_firma
FROM public.ventas;
