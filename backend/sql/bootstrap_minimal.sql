-- Extensiones
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==== Catálogos base ====
CREATE TABLE IF NOT EXISTS almacenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT UNIQUE NOT NULL,
  nombre TEXT NOT NULL,
  tipo TEXT DEFAULT 'TECNICO',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS materiales (
  id INTEGER PRIMARY KEY,
  codigo TEXT UNIQUE NOT NULL,
  nombre TEXT NOT NULL,
  precio NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- ==== Kardex ====
CREATE TABLE IF NOT EXISTS inventario_movimientos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  almacen_id UUID NOT NULL REFERENCES almacenes(id) ON DELETE CASCADE,
  material_id INTEGER NOT NULL REFERENCES materiales(id) ON DELETE RESTRICT,
  cantidad NUMERIC(14,2) NOT NULL,
  motivo TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kardex_almacen    ON inventario_movimientos(almacen_id);
CREATE INDEX IF NOT EXISTS idx_kardex_material   ON inventario_movimientos(material_id);
CREATE INDEX IF NOT EXISTS idx_kardex_created_at ON inventario_movimientos(created_at);

-- ==== Usuarios/Ordenes mínimos para /v1/jobs ====
CREATE TABLE IF NOT EXISTS usuarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT,
  estado TEXT DEFAULT 'instalado',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ordenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT NOT NULL,
  estado TEXT NOT NULL DEFAULT 'agendada',
  tecnico_id INTEGER NULL,
  tipo TEXT NOT NULL,
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,
  usuario_id UUID NOT NULL REFERENCES usuarios(id),
  cerrada_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ordenes_usuario ON ordenes(usuario_id);

-- ==== Equipos (para /v1/equipos/*) ====
CREATE TABLE IF NOT EXISTS equipos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL,
  sn TEXT UNIQUE NOT NULL,
  mac TEXT UNIQUE NOT NULL,
  estandar TEXT,
  estado TEXT NOT NULL DEFAULT 'EN_STOCK',
  owner_tipo TEXT,
  owner_id TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==== Técnicos y relación con almacenes ====
CREATE TABLE IF NOT EXISTS tecnicos (
  id INTEGER PRIMARY KEY,
  nombre TEXT,
  almacen_id UUID REFERENCES almacenes(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==== Semillas ====
INSERT INTO almacenes (id, codigo, nombre, tipo)
VALUES ('62ebd37f-44c4-499d-b9ed-7bee75b09275', 'TEC-6', 'Almacén Técnico 6', 'TECNICO')
ON CONFLICT (id) DO NOTHING;

INSERT INTO materiales (id, codigo, nombre, precio) VALUES
  (3, 'd04b48ca-2731-4b70-b973-6a2af80a92f4', 'defef420-52cf-472c-8413-3ac6f4195fdd', 0),
  (4, 'MAT-CABLE', 'Cable UTP', 0),
  (5, 'DROP-FO',   'Drop FO',   0)
ON CONFLICT (id) DO NOTHING;

-- 5 usuarios de prueba
INSERT INTO usuarios (id, nombre, estado)
SELECT gen_random_uuid(), 'Usuario ' || gs::text, 'instalado'
FROM generate_series(1,5) AS gs
ON CONFLICT DO NOTHING;

-- Stock semilla en TEC-6 (28, 4, 136)
DELETE FROM inventario_movimientos WHERE almacen_id = '62ebd37f-44c4-499d-b9ed-7bee75b09275';
INSERT INTO inventario_movimientos (almacen_id, material_id, cantidad, motivo) VALUES
  ('62ebd37f-44c4-499d-b9ed-7bee75b09275', 3,  28, 'seed TEC-6 ONT'),
  ('62ebd37f-44c4-499d-b9ed-7bee75b09275', 4,   4, 'seed TEC-6 CABLE'),
  ('62ebd37f-44c4-499d-b9ed-7bee75b09275', 5, 136, 'seed TEC-6 DROP');

-- Técnicos
INSERT INTO tecnicos (id, nombre, almacen_id)
VALUES (6, 'Técnico 6', '62ebd37f-44c4-499d-b9ed-7bee75b09275')
ON CONFLICT (id) DO UPDATE SET almacen_id = EXCLUDED.almacen_id;

-- ==== Vistas esperadas por la API ====
CREATE OR REPLACE VIEW public.stock_almacen AS
SELECT
  a.id      AS almacen_id,
  a.codigo  AS almacen_codigo,
  a.nombre  AS almacen_nombre,
  m.id      AS material_id,
  m.codigo  AS material_codigo,
  m.nombre  AS material_nombre,
  COALESCE(SUM(im.cantidad), 0)::numeric(14,2) AS cantidad
FROM almacenes a
JOIN inventario_movimientos im ON im.almacen_id = a.id
JOIN materiales m ON m.id = im.material_id
GROUP BY a.id, a.codigo, a.nombre, m.id, m.codigo, m.nombre;

CREATE OR REPLACE VIEW public.stock_tecnico AS
SELECT
  t.id AS tecnico_id,
  sa.*
FROM tecnicos t
JOIN public.stock_almacen sa ON sa.almacen_id = t.almacen_id;
