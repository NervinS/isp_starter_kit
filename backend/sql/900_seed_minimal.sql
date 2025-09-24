-- Idempotent mini-seed básico para entorno local/dev.

-- 1) Técnico demo
INSERT INTO tecnicos (id, codigo, nombre, activo)
VALUES (gen_random_uuid(), 'TEC-0001', 'Técnico Demo', TRUE)
ON CONFLICT (codigo) DO UPDATE
  SET nombre = EXCLUDED.nombre,
      activo = EXCLUDED.activo;

-- 2) Material base
INSERT INTO materiales (codigo, nombre, precio)
VALUES ('MAT-0001', 'Conector RJ45', 1200.00)
ON CONFLICT (codigo) DO UPDATE
  SET nombre = EXCLUDED.nombre,
      precio = EXCLUDED.precio;

-- 3) Orden semilla asignada al técnico (no forzamos estado si ya existe)
INSERT INTO ordenes (id, codigo, tecnico_id, estado)
SELECT gen_random_uuid(), 'ORD-SEED-1003', t.id, 'agendada'
FROM tecnicos t
WHERE t.codigo = 'TEC-0001'
ON CONFLICT (codigo) DO UPDATE
  SET tecnico_id = EXCLUDED.tecnico_id
  WHERE ordenes.tecnico_id IS DISTINCT FROM EXCLUDED.tecnico_id;

-- Nota: dejamos inv_tecnico sin tocar; los smokes ajustan stock vía API.
