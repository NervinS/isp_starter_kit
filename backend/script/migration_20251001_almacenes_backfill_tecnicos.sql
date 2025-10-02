-- Backfill almacenes legados (con tecnico_id) para tener codigo/nombre/tipo coherentes

-- 1) Asegura columnas clave (defensivo)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='codigo') THEN
    ALTER TABLE almacenes ADD COLUMN codigo TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='nombre') THEN
    ALTER TABLE almacenes ADD COLUMN nombre TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='tipo') THEN
    ALTER TABLE almacenes ADD COLUMN tipo TEXT;
  END IF;
END$$;

-- 2) Backfill para almacenes de técnicos:
--    Si tecnicos.codigo existe, úsalo; si no, genera TEC-<uuid8>
DO $$
DECLARE
  has_tecnicos_codigo boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM information_schema.columns
     WHERE table_name='tecnicos' AND column_name='codigo'
  ) INTO has_tecnicos_codigo;

  IF has_tecnicos_codigo THEN
    EXECUTE $SQL$
      UPDATE almacenes a
      SET
        codigo = COALESCE(t.codigo, 'TEC-' || SUBSTRING(t.id::text, 1, 8)),
        nombre = COALESCE('Almacén Técnico ' || t.nombre, 'Almacén Técnico'),
        tipo   = 'tecnico'
      FROM tecnicos t
      WHERE a.tecnico_id = t.id
        AND (a.codigo IS NULL OR a.codigo = '')
    $SQL$;
  ELSE
    EXECUTE $SQL$
      UPDATE almacenes a
      SET
        codigo = 'TEC-' || SUBSTRING(t.id::text, 1, 8),
        nombre = COALESCE('Almacén Técnico ' || t.nombre, 'Almacén Técnico'),
        tipo   = 'tecnico'
      FROM tecnicos t
      WHERE a.tecnico_id = t.id
        AND (a.codigo IS NULL OR a.codigo = '')
    $SQL$;
  END IF;
END$$;

-- 3) Backfill para filas sin tecnico_id y sin codigo (residuales): generamos ALM-<uuid8>
UPDATE almacenes a
SET
  codigo = 'ALM-' || SUBSTRING(a.id::text, 1, 8),
  nombre = COALESCE(NULLIF(a.nombre, ''), 'Almacén'),
  tipo   = COALESCE(NULLIF(a.tipo, ''), 'principal')
WHERE (a.tecnico_id IS NULL OR a.tecnico_id::text = '')
  AND (a.codigo IS NULL OR a.codigo = '');

-- 4) Evita duplicados: conserva la más antigua y reasigna las otras
WITH dups AS (
  SELECT codigo, MIN(id::text) AS keep_id_txt
  FROM almacenes
  WHERE codigo IS NOT NULL AND codigo <> ''
  GROUP BY codigo
  HAVING COUNT(*) > 1
)
UPDATE almacenes a
SET codigo = 'ALM-' || SUBSTRING(a.id::text, 1, 8)
FROM dups d
WHERE a.codigo = d.codigo
  AND a.id::text <> d.keep_id_txt;

-- 5) Re-asegura UNIQUE (codigo)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname='uq_almacenes_codigo'
       AND conrelid='almacenes'::regclass
  ) THEN
    ALTER TABLE almacenes ADD CONSTRAINT uq_almacenes_codigo UNIQUE (codigo);
  END IF;
END$$;

-- 6) (Opcional) endurecer NOT NULL si ya no quedan nulos
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM almacenes WHERE codigo IS NULL OR codigo='') THEN
    BEGIN
      ALTER TABLE almacenes ALTER COLUMN codigo SET NOT NULL;
    EXCEPTION WHEN OTHERS THEN
      -- si falla por legado, lo dejamos laxo
      NULL;
    END;
  END IF;
END$$;
