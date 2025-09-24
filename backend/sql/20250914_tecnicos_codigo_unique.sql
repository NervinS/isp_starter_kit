-- Asegura unicidad del código de técnico
CREATE UNIQUE INDEX IF NOT EXISTS ux_tecnicos_codigo
  ON tecnicos(codigo);
