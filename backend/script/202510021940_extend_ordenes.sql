-- migration ..202510021940_extend_ordenes.sql
ALTER TABLE ordenes
  ADD COLUMN IF NOT EXISTS tipo TEXT, -- 'INS','MAN','COR','REC','BAJ','TRA','CMB','RCT'
  ADD COLUMN IF NOT EXISTS payload_abierto JSONB,
  ADD COLUMN IF NOT EXISTS payload_cierre JSONB,
  ADD COLUMN IF NOT EXISTS evidencias JSONB; -- { fotos:[...], firma:{...}, otros:[...] }
CREATE INDEX IF NOT EXISTS ix_ordenes_tipo ON ordenes(tipo);
CREATE INDEX IF NOT EXISTS ix_ordenes_estado ON ordenes(estado);
CREATE INDEX IF NOT EXISTS ix_ordenes_tecnico ON ordenes(tecnico_id);
