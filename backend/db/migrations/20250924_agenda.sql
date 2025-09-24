-- AGENDA: columnas necesarias
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS agendado_para date;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS turno text;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS agendada_at timestamptz;

-- Cancelar / Anular: motivos y marcas
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS motivo_cancelacion text;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS motivo_codigo text;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS cancelada_at timestamptz;
ALTER TABLE ordenes ADD COLUMN IF NOT EXISTS anulada_at timestamptz;

-- Índices de consulta
CREATE INDEX IF NOT EXISTS ix_ordenes_agendado_para ON ordenes(agendado_para);
CREATE INDEX IF NOT EXISTS ix_ordenes_turno          ON ordenes(turno);

-- Unicidad de codigo (si no existiera)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'uq_ordenes_codigo'
  ) THEN
    CREATE UNIQUE INDEX uq_ordenes_codigo ON ordenes(codigo);
  END IF;
END $$;

-- DEFAULT de codigo robusto para DEV (evita colisiones por inserciones simultáneas)
ALTER TABLE ordenes
  ALTER COLUMN codigo SET DEFAULT
    ('INS-' ||
     to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' ||
     substr(md5(uuid_generate_v4()::text),1,4));
