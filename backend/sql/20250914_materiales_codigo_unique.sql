-- sql/20250914_materiales_codigo_unique.sql
CREATE UNIQUE INDEX IF NOT EXISTS ux_materiales_codigo
  ON materiales(codigo);
