-- Sincroniza la secuencia/identity de tecnicos.id con el MAX(id) actual.
DO $$
DECLARE
  seq_name regclass;
  max_id   bigint;
BEGIN
  -- Funciona tanto para IDENTITY como para SERIAL
  SELECT pg_get_serial_sequence('public.tecnicos','id')::regclass INTO seq_name;

  IF seq_name IS NULL THEN
    RAISE NOTICE 'tecnicos.id no usa secuencia (o no existe); no se ajusta.';
    RETURN;
  END IF;

  SELECT COALESCE(MAX(id),0) INTO max_id FROM public.tecnicos;

  -- Deja la secuencia en MAX(id) para que el próximo nextval() sea MAX(id)+1
  EXECUTE format('SELECT setval(%s, %s)', quote_literal(seq_name::text), max_id);
  RAISE NOTICE 'Secuencia % ajustada a %', seq_name::text, max_id;
END$$;
