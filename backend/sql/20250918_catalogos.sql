-- 20250918_catalogos.sql (idempotente)
-- Catálogos base + Motivos de Reagenda

BEGIN;

-- MUNICIPIOS/VÍAS/SECTORES (si ya existen, no pasa nada)
CREATE TABLE IF NOT EXISTS municipios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS vias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS sectores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL UNIQUE
);

-- MOTIVOS DE REAGENDA (SIEMPRE TABLA, nunca vista)
CREATE TABLE IF NOT EXISTS motivos_reagenda (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT UNIQUE,
  nombre TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  orden INT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices de ayuda (idempotentes)
CREATE INDEX IF NOT EXISTS ix_mre_activo ON motivos_reagenda(activo);
CREATE INDEX IF NOT EXISTS ix_mre_orden ON motivos_reagenda(orden);
CREATE INDEX IF NOT EXISTS ix_mre_nombre ON motivos_reagenda((lower(nombre)));

-- Seed mínimo (no duplica)
INSERT INTO municipios (id, nombre) VALUES
  ('00000000-0000-0000-0000-000000000001','Municipio A')
ON CONFLICT (id) DO NOTHING;

INSERT INTO vias (id, nombre) VALUES
  ('00000000-0000-0000-0000-000000000001','Avenida')
ON CONFLICT (id) DO NOTHING;

INSERT INTO sectores (id, nombre) VALUES
  ('00000000-0000-0000-0000-000000000001','Centro')
ON CONFLICT (id) DO NOTHING;

-- Motivos base (no duplica por código)
INSERT INTO motivos_reagenda (codigo, nombre, activo, orden) VALUES
  ('CLI_NO_DISP',     'Cliente no disponible', TRUE,  10),
  ('DIRECCION_ERR',   'Dirección errónea/incompleta', TRUE, 20),
  ('FALTA_MATERIAL',  'Falta de material', TRUE,      30),
  ('CLIMA',           'Condiciones climáticas', TRUE, 40)
ON CONFLICT (codigo) DO NOTHING;

COMMIT;

