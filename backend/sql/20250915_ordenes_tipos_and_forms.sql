-- 20250915_ordenes_tipos_and_forms.sql
-- Extiende 'ordenes' y crea tablas auxiliares para evidencias, eventos y almacén principal.

BEGIN;

-- 1) Extensiones mínimas
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2) Columnas nuevas en 'ordenes' (opcionales / compatibles)
ALTER TABLE ordenes
  ADD COLUMN IF NOT EXISTS tipo TEXT, -- MAN|COR|REC|BAJ|TRA|CMB|RCT|INS
  ADD COLUMN IF NOT EXISTS cliente_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS servicio_snapshot JSONB,
  ADD COLUMN IF NOT EXISTS form_data JSONB,
  ADD COLUMN IF NOT EXISTS auto_agendada BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_cerrada BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS agendada_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cerrada_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pdf_key TEXT;

-- 3) Índices de apoyo
CREATE INDEX IF NOT EXISTS ix_ordenes_tipo ON ordenes (tipo);
CREATE INDEX IF NOT EXISTS ix_ordenes_estado ON ordenes (estado);

-- 4) Constraint de dominio de 'tipo' (agregar si no existe)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   pg_constraint
    WHERE  conname = 'ck_ordenes_tipo_dom'
  ) THEN
    ALTER TABLE ordenes
      ADD CONSTRAINT ck_ordenes_tipo_dom
      CHECK (tipo IS NULL OR tipo IN ('MAN','COR','REC','BAJ','TRA','CMB','RCT','INS'));
  END IF;
END$$;

-- 5) Tabla de adjuntos (fotos, firma, etc.)
CREATE TABLE IF NOT EXISTS orden_adjuntos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('foto','firma','otro')),
  key TEXT NOT NULL, -- ej: minio://bucket/path
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_oadj_orden ON orden_adjuntos (orden_id);

-- 6) Eventos de auditoría (creada/agendada/cerrada/pdf_generado/etc.)
CREATE TABLE IF NOT EXISTS orden_eventos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
  evento TEXT NOT NULL,
  meta JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_oevt_orden ON orden_eventos (orden_id);

-- 7) Inventario principal (almacén general)
CREATE TABLE IF NOT EXISTS inv_principal (
  material_id INT PRIMARY KEY REFERENCES materiales(id),
  cantidad NUMERIC(12,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8) Movimientos de inventario (principal y traspasos a técnicos)
CREATE TABLE IF NOT EXISTS inv_movimientos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL CHECK (tipo IN ('entrada','salida','traspaso_a_tecnico','devolucion_de_tecnico')),
  material_id INT NOT NULL REFERENCES materiales(id),
  tecnico_id UUID NULL REFERENCES tecnicos(id),
  cantidad NUMERIC(12,3) NOT NULL,
  nota TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_invmov_material ON inv_movimientos(material_id);
CREATE INDEX IF NOT EXISTS ix_invmov_tecnico ON inv_movimientos(tecnico_id);

-- 9) Helper opcional: prefijo por tipo
CREATE OR REPLACE FUNCTION orden_codigo_prefijo(p_tipo TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN CASE p_tipo
    WHEN 'MAN' THEN 'MAN'
    WHEN 'COR' THEN 'COR'
    WHEN 'REC' THEN 'REC'
    WHEN 'BAJ' THEN 'BAJ' -- estandarizamos BAJ (no BJA)
    WHEN 'TRA' THEN 'TRA'
    WHEN 'CMB' THEN 'CMB'
    WHEN 'RCT' THEN 'RCT'
    WHEN 'INS' THEN 'INS'
    ELSE NULL
  END;
END$$;

COMMIT;
