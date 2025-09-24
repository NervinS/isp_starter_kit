-- sql/2025-09-19_init_ordenes.sql
-- Bootstrap mínimo y seguro para módulo Órdenes + líneas de materiales.
-- Idempotente: usa IF NOT EXISTS / ON CONFLICT para poder re-ejecutarse.

-- 0) Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) Catálogo de materiales
CREATE TABLE IF NOT EXISTS materiales (
  id           SERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL UNIQUE,
  precio       NUMERIC(12,2) NOT NULL DEFAULT 0,
  creado_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  codigo       TEXT NOT NULL UNIQUE,
  tipo         TEXT,
  es_serial    BOOLEAN NOT NULL DEFAULT FALSE
);

-- 2) Órdenes (alineado con el entity actual)
CREATE TABLE IF NOT EXISTS ordenes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo            TEXT NOT NULL,
  estado            TEXT NOT NULL DEFAULT 'agendada',
  subtotal          NUMERIC(12,2) NOT NULL DEFAULT 0,
  total             NUMERIC(12,2) NOT NULL DEFAULT 0,
  cerrada_at        TIMESTAMPTZ,
  tecnico_id        UUID,
  creado_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  iniciada_at       TIMESTAMPTZ,
  firma_key         TEXT,
  pdf_url           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo              TEXT,
  cliente_snapshot  JSONB,
  servicio_snapshot JSONB,
  form_data         JSONB,
  auto_agendada     BOOLEAN DEFAULT FALSE,
  auto_cerrada      BOOLEAN DEFAULT FALSE,
  agendada_at       TIMESTAMPTZ,
  pdf_key           TEXT,
  agendado_para     DATE,
  turno             TEXT,
  observaciones     TEXT,
  usuario_id        UUID,
  snapshot_tecnico  JSONB NOT NULL DEFAULT '{}'::jsonb,
  cierre_token      UUID,
  CONSTRAINT ordenes_codigo_key UNIQUE (codigo),
  CONSTRAINT ux_ordenes_tipo_codigo UNIQUE (tipo, codigo),
  CONSTRAINT ck_ordenes_tipo_dom CHECK (
    tipo IS NULL OR tipo IN ('MAN','COR','REC','BAJ','TRA','CMB','RCT','INS')
  )
);

-- Índices útiles para filtros/agendas (idempotentes)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_ordenes_agenda') THEN
    CREATE INDEX ix_ordenes_agenda ON ordenes(agendado_para, turno);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_ordenes_estado') THEN
    CREATE INDEX ix_ordenes_estado ON ordenes(estado);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_ordenes_tipo') THEN
    CREATE INDEX ix_ordenes_tipo ON ordenes(tipo);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_ordenes_usuario') THEN
    CREATE INDEX ix_ordenes_usuario ON ordenes(usuario_id);
  END IF;
  -- Unique parcial sobre cierre_token cuando no es NULL
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_ordenes_cierre_token') THEN
    CREATE UNIQUE INDEX ux_ordenes_cierre_token ON ordenes(cierre_token) WHERE cierre_token IS NOT NULL;
  END IF;
END
$$;

-- 3) Líneas de materiales por orden
CREATE TABLE IF NOT EXISTS orden_materiales (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id         UUID NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
  material_id      INTEGER NOT NULL REFERENCES materiales(id) ON DELETE RESTRICT,
  cantidad         NUMERIC(12,3) NOT NULL DEFAULT 0,
  precio_unitario  NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_calculado  NUMERIC(14,2) GENERATED ALWAYS AS (ROUND(cantidad * precio_unitario, 2)) STORED,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ux_orden_materiales_orden_mat UNIQUE (orden_id, material_id)
);

-- 4) Semillas mínimas (seguras)
-- Material estándar usado en pruebas
INSERT INTO materiales (codigo, nombre, precio, tipo, es_serial)
VALUES ('MAT-0001','Conector RJ45',1200,'CONSUMIBLE',FALSE)
ON CONFLICT (codigo) DO NOTHING;

-- Orden de mantenimiento de prueba (solo si no existe)
INSERT INTO ordenes (codigo, tipo, estado, agendado_para, turno)
SELECT 'MAN-000001','MAN','creada', CURRENT_DATE, 'am'
WHERE NOT EXISTS (SELECT 1 FROM ordenes WHERE codigo='MAN-000001');
