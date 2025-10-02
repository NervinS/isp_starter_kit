-- Sincroniza la secuencia/identity de materiales.id con el MAX(id) actual (si aplica).
DO $$
DECLARE
  seq_name regclass;
  max_id   bigint;
BEGIN
  SELECT pg_get_serial_sequence('public.materiales','id')::regclass INTO seq_name;

  IF seq_name IS NULL THEN
    RAISE NOTICE 'materiales.id no usa secuencia (o no existe); no se ajusta.';
    RETURN;
  END IF;

  SELECT COALESCE(MAX(id),0) INTO max_id FROM public.materiales;
  EXECUTE format('SELECT setval(%s, %s)', quote_literal(seq_name::text), max_id);
  RAISE NOTICE 'Secuencia % ajustada a %', seq_name::text, max_id;
END$$;
