DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.constraint_column_usage ccu
    JOIN information_schema.table_constraints tc
      ON tc.constraint_name = ccu.constraint_name
    WHERE ccu.table_name='ordenes' AND ccu.column_name='tipo' AND tc.constraint_type='CHECK'
  ) THEN
    EXECUTE $chk$
      ALTER TABLE ordenes
      ADD CONSTRAINT chk_ordenes_tipo
      CHECK (tipo IN ('INS','MAN','COR','REC','BAJ','TRA','CMB','RCT'))
    $chk$;
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END$$;
