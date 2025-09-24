-- db/migrations/20250924_reagendar_motivo.sql
ALTER TABLE ordenes
  ADD COLUMN IF NOT EXISTS motivo_reagenda_codigo text,
  ADD COLUMN IF NOT EXISTS motivo_reagenda text;

-- Index opcional si vas a filtrar por el código
CREATE INDEX IF NOT EXISTS ix_ordenes_motivo_reagenda_codigo
  ON ordenes(motivo_reagenda_codigo);
