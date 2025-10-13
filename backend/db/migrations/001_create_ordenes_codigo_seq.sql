-- 001_create_ordenes_codigo_seq.sql
CREATE SEQUENCE IF NOT EXISTS public.ordenes_codigo_seq;

-- Si ya existen códigos tipo COR-000123 / REC-000456, sincroniza el contador:
SELECT setval(
  'public.ordenes_codigo_seq',
  COALESCE(
    (SELECT MAX((regexp_replace(codigo, '^[A-Z]+-', '')::bigint)) FROM public.ordenes),
    0
  )
);
