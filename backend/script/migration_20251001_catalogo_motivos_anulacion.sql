-- 2025-10-01: catálogo motivos de anulación (idempotente)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='catalogo_motivos_anulacion'
  ) THEN
    CREATE TABLE public.catalogo_motivos_anulacion (
      id          bigserial PRIMARY KEY,
      nombre      text NOT NULL UNIQUE,
      activo      boolean NOT NULL DEFAULT true,
      created_at  timestamptz NOT NULL DEFAULT now()
    );
  END IF;
END$$;

-- semillas mínimas (idempotentes)
INSERT INTO public.catalogo_motivos_anulacion (nombre)
SELECT x.nombre
FROM (VALUES
  ('Doble registro'),
  ('Error en los datos'),
  ('Orden duplicada'),
  ('Solicitud del cliente')
) AS x(nombre)
WHERE NOT EXISTS (SELECT 1 FROM public.catalogo_motivos_anulacion c WHERE c.nombre = x.nombre);
