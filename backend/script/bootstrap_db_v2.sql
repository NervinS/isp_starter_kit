-- Extensión para UUID
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- === TECNICOS ===
CREATE TABLE IF NOT EXISTS tecnicos (
  id INT PRIMARY KEY,
  nombre TEXT NOT NULL DEFAULT 'Técnico'
);

-- 10 técnicos (1..10)
INSERT INTO tecnicos(id,nombre)
SELECT i, 'Técnico '||i FROM generate_series(1,10) i
ON CONFLICT (id) DO NOTHING;

-- === ALMACENES (UUID) ===
CREATE TABLE IF NOT EXISTS almacenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL CHECK (tipo IN ('principal','tecnico')),
  tecnico_id INT NULL REFERENCES tecnicos(id)
);

-- Almacén principal (uno)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM almacenes WHERE tipo='principal') THEN
    INSERT INTO almacenes (tipo) VALUES ('principal');
  END IF;
END $$;

-- Un almacén por técnico si no existe
INSERT INTO almacenes (id, tipo, tecnico_id)
SELECT gen_random_uuid(), 'tecnico', t.id
FROM tecnicos t
LEFT JOIN almacenes a ON a.tecnico_id = t.id
WHERE a.id IS NULL;

-- === MATERIALES ===
CREATE TABLE IF NOT EXISTS materiales (
  id INT PRIMARY KEY,
  codigo TEXT UNIQUE,
  nombre TEXT NOT NULL,
  precio NUMERIC(12,2) NOT NULL DEFAULT 0
);

INSERT INTO materiales (id,codigo,nombre,precio) VALUES
  (1,'MAT-1','Material 1',1000),
  (2,'MAT-2','Material 2',2000),
  (3,'MAT-3','Material 3',3000)
ON CONFLICT (id) DO NOTHING;

-- === STOCK POR ALMACEN ===
CREATE TABLE IF NOT EXISTS stock_almacen (
  almacen_id UUID NOT NULL REFERENCES almacenes(id) ON DELETE CASCADE,
  material_id INT NOT NULL REFERENCES materiales(id),
  cantidad INT NOT NULL DEFAULT 0,
  PRIMARY KEY (almacen_id, material_id)
);

-- === INV_TECNICO (copia rápida para endpoint) ===
CREATE TABLE IF NOT EXISTS inv_tecnico (
  tecnico_id INT NOT NULL REFERENCES tecnicos(id) ON DELETE CASCADE,
  material_id INT NOT NULL REFERENCES materiales(id),
  cantidad INT NOT NULL DEFAULT 0,
  PRIMARY KEY (tecnico_id, material_id)
);

-- Seed: técnico 6 tiene 10 unidades del material 3
WITH alm_tecnico AS (
  SELECT id AS almacen_id
  FROM almacenes
  WHERE tipo='tecnico' AND tecnico_id=6
),
upsert_stock AS (
  INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
  SELECT a.almacen_id, 3, 10 FROM alm_tecnico a
  ON CONFLICT (almacen_id, material_id) DO UPDATE SET cantidad=EXCLUDED.cantidad
  RETURNING 1
)
INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
VALUES (6,3,10)
ON CONFLICT (tecnico_id, material_id) DO UPDATE SET cantidad=EXCLUDED.cantidad;

-- === MOVIMIENTOS (usado por la API) ===
CREATE TABLE IF NOT EXISTS movimientos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key TEXT UNIQUE,
  tipo TEXT NOT NULL CHECK (tipo IN ('ingreso','egreso','ajuste','transferencia')),
  almacen_origen_id UUID NULL REFERENCES almacenes(id),
  almacen_destino_id UUID NULL REFERENCES almacenes(id),
  material_id INT NOT NULL REFERENCES materiales(id),
  cantidad INT NOT NULL CHECK (cantidad > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- === ORDENES (campos mínimos esperados por la API v2) ===
CREATE TABLE IF NOT EXISTS ordenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT UNIQUE NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'INS',
  estado TEXT NOT NULL DEFAULT 'creada',
  agendado_para DATE NULL,
  turno TEXT NULL,
  agendada_at TIMESTAMPTZ NULL,
  tecnico_id INT NULL REFERENCES tecnicos(id),
  iniciada_at TIMESTAMPTZ NULL,
  cerrada_at TIMESTAMPTZ NULL,
  cancelada_at TIMESTAMPTZ NULL,
  motivo_cancelacion TEXT NULL
);

-- === CATALOGO MOTIVOS REAGENDA ===
CREATE TABLE IF NOT EXISTS public.catalogo_motivos_reagenda (
  id SERIAL PRIMARY KEY,
  codigo TEXT UNIQUE,
  nombre TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.catalogo_motivos_reagenda (codigo, nombre) VALUES
  ('cliente-ausente','Cliente no disponible'),
  ('cliente-no-disponible','Cliente reprograma'),
  ('cliente-no-estaba','Cliente no estaba'),
  ('direccion-incorrecta','Dirección incorrecta'),
  ('clima','Condiciones climáticas'),
  ('falla-tecnica','Falla técnica'),
  ('otro','Otro')
ON CONFLICT (codigo) DO NOTHING;
