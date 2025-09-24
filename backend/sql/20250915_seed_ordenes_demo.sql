-- sql/20250915_seed_ordenes_demo.sql
BEGIN;

-- 1) Semilla de tipos (solo si existe la tabla)
DO $$
BEGIN
  IF to_regclass('public.orden_tipos') IS NOT NULL THEN
    INSERT INTO orden_tipos (codigo, nombre)
    SELECT v.codigo, v.nombre
    FROM (VALUES
      ('instalacion','Instalación'),
      ('reparacion','Reparación'),
      ('mantenimiento','Mantenimiento')
    ) AS v(codigo, nombre)
    ON CONFLICT (codigo) DO NOTHING;
  END IF;
END$$;

-- 2) Asignar tipo 'instalacion' a ORD-SEED-1003 (solo si existe la columna tipo_id)
DO $$
BEGIN
  IF to_regclass('public.orden_tipos') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'ordenes'
         AND column_name = 'tipo_id'
     )
  THEN
    -- Usamos EXECUTE para evitar problemas de tipos si tipo_id no es UUID
    EXECUTE $q$
      UPDATE ordenes o
      SET tipo_id = t.id
      FROM orden_tipos t
      WHERE o.codigo = 'ORD-SEED-1003'
        AND t.codigo = 'instalacion'
        AND (o.tipo_id IS DISTINCT FROM t.id)
    $q$;
  END IF;
END$$;

-- 3) Crear 2 órdenes demo para TEC-0001 si no existen
WITH tec AS (
  SELECT id AS tecnico_id
  FROM tecnicos
  WHERE codigo = 'TEC-0001'
  LIMIT 1
)
INSERT INTO ordenes (id, codigo, tecnico_id, estado, created_at, updated_at)
SELECT gen_random_uuid(), v.codigo, tec.tecnico_id, 'agendada', now(), now()
FROM tec
JOIN (VALUES ('ORD-DEMO-2001'), ('ORD-DEMO-2002')) AS v(codigo) ON TRUE
WHERE NOT EXISTS (SELECT 1 FROM ordenes o WHERE o.codigo = v.codigo);

COMMIT;
