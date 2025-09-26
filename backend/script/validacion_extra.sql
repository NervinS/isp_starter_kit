-- Tipos de columnas clave
SELECT 'orden_materiales.material_id' AS col, data_type
FROM information_schema.columns
WHERE table_name='orden_materiales' AND column_name='material_id'
UNION ALL
SELECT 'orden_materiales.material_id_int', data_type
FROM information_schema.columns
WHERE table_name='orden_materiales' AND column_name='material_id_int'
UNION ALL
SELECT 'inv_tecnico.material_id', data_type
FROM information_schema.columns
WHERE table_name='inv_tecnico' AND column_name='material_id';

-- Duplicados residuales
SELECT tecnico_id, material_id, COUNT(*) c
FROM inv_tecnico
GROUP BY 1,2
HAVING COUNT(*)>1;

-- (Opcional) Reponer UNIQUE si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public'
      AND tablename='inv_tecnico'
      AND indexname='inv_tecnico_tecnico_id_material_id_key'
  ) THEN
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT inv_tecnico_tecnico_id_material_id_key UNIQUE (tecnico_id, material_id);
  END IF;
END$$;
