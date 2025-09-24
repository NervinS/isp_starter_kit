-- sql/2025-09-19_init_catalogos_tecnicos.sql
-- Tablas necesarias para smokes de Catálogos y Técnicos (mínimas, sin romper nada existente)

-- Extensión para UUID (por si no está)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================
-- CATÁLOGOS: motivos_reagenda
-- =========================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'motivos_reagenda') THEN
    CREATE TABLE motivos_reagenda (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      nombre        TEXT NOT NULL UNIQUE,
      activo        BOOLEAN NOT NULL DEFAULT TRUE,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ
    );
  END IF;
END
$$;

-- Semillas básicas (idempotentes)
INSERT INTO motivos_reagenda (nombre, activo) VALUES
  ('Clima', TRUE)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO motivos_reagenda (nombre, activo) VALUES
  ('Cliente ausente', TRUE)
ON CONFLICT (nombre) DO NOTHING;

-- Opcional: si algún endpoint usa la variante underscore /items,
-- puedes respaldarlo con la MISMA tabla para no duplicar esquema.
-- Si en tu código existe una entidad 'motivos_reagenda_items', crea esta vista:
CREATE OR REPLACE VIEW motivos_reagenda_items AS
  SELECT id, nombre, activo, created_at, updated_at FROM motivos_reagenda;

-- =========================
-- TÉCNICOS: tabla mínima para scripts que consultan DB
-- =========================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tecnicos') THEN
    CREATE TABLE tecnicos (
      id         UUID PRIMARY KEY,
      codigo     TEXT NOT NULL UNIQUE,
      activo     BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  END IF;
END
$$;

-- Inserta el técnico que ya vienes usando en pruebas (id == TEC_ID)
-- Ajusta el código si quieres algo más amigable.
INSERT INTO tecnicos (id, codigo, activo)
VALUES ('a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec', 'TEC-0001', TRUE)
ON CONFLICT (id) DO NOTHING;
