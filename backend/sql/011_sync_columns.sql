BEGIN;

-- === Timestamps en tablas clave (si faltan) ===
ALTER TABLE public.tecnicos
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.materiales
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.ordenes
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.orden_materiales
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.inv_tecnico
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- === materiales.codigo (si falta) ===
ALTER TABLE public.materiales
  ADD COLUMN IF NOT EXISTS codigo text;

-- Rellenar códigos donde estén NULL, con formato MAT-0001, MAT-0002, ...
WITH s AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn
  FROM public.materiales
)
UPDATE public.materiales m
SET codigo = COALESCE(m.codigo, 'MAT-' || LPAD(s.rn::text, 4, '0'))
FROM s
WHERE m.id = s.id;

-- Hacerlo NOT NULL y único (si no existiera el índice)
ALTER TABLE public.materiales
  ALTER COLUMN codigo SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  c.relname = 'ux_materiales_codigo'
    AND    n.nspname = 'public'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX ux_materiales_codigo ON public.materiales (codigo)';
  END IF;
END$$;

COMMIT;
