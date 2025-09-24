-- 20250924_catalogos_motivos.sql
-- Asegura columnas y orden para el endpoint /v1/catalogos/motivos-reagenda

DO $$
BEGIN
  -- Columna 'orden'
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='catalogo_motivos_reagenda' AND column_name='orden'
  ) THEN
    ALTER TABLE catalogo_motivos_reagenda ADD COLUMN orden integer;
  END IF;
END
$$;

-- Valores por defecto de orden (idempotente)
UPDATE catalogo_motivos_reagenda SET orden =
  CASE codigo
    WHEN 'cliente-ausente' THEN 10
    WHEN 'cobertura'       THEN 20
    WHEN 'falla-interna'   THEN 30
    WHEN 'lluvia'          THEN 40
    WHEN 'otro'            THEN 50
    ELSE 999
  END
WHERE orden IS NULL;

CREATE INDEX IF NOT EXISTS ix_catalogo_motivos_reagenda_orden ON catalogo_motivos_reagenda(orden);

-- Vista plural (compat) si se usa en algún lado
CREATE OR REPLACE VIEW catalogos_motivos_reagenda AS
SELECT id, codigo, nombre, COALESCE(activo,true) AS activo, orden
FROM catalogo_motivos_reagenda;
