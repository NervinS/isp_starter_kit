-- Agrega columna 'telefono' en tecnicos si no existe (el servicio de cierre la selecciona)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='tecnicos' AND column_name='telefono'
  ) THEN
    ALTER TABLE tecnicos ADD COLUMN telefono text NULL;
  END IF;
END$$;

-- Opcional: setear algún teléfono de demo para TEC-0001
UPDATE tecnicos
SET telefono = COALESCE(telefono, '+57 300 000 0001')
WHERE codigo = 'TEC-0001';
