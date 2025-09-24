-- 000_schema_core.sql
-- Esquema mínimo para que la API arranque y los constraints existentes apliquen

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- para gen_random_uuid()

-- =======================
-- TÉCNICOS
-- =======================
CREATE TABLE IF NOT EXISTS public.tecnicos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo     text NOT NULL UNIQUE,
  nombre     text,
  activo     boolean NOT NULL DEFAULT true,
  creado_at  timestamptz NOT NULL DEFAULT now()
);

-- =======================
-- MATERIALES
--  - id numérico (coincide con el código que usa tu servicio)
-- =======================
CREATE TABLE IF NOT EXISTS public.materiales (
  id         serial PRIMARY KEY,
  nombre     text NOT NULL UNIQUE,
  precio     numeric(12,2) NOT NULL DEFAULT 0,
  creado_at  timestamptz NOT NULL DEFAULT now()
);

-- =======================
-- STOCK POR TÉCNICO
--  - SIN índices únicos aquí (los agrega 001_inv_tecnico_constraints.sql)
-- =======================
CREATE TABLE IF NOT EXISTS public.inv_tecnico (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tecnico_id  uuid    NOT NULL REFERENCES public.tecnicos(id) ON DELETE CASCADE,
  material_id integer NOT NULL REFERENCES public.materiales(id) ON DELETE RESTRICT,
  cantidad    numeric(12,3) NOT NULL DEFAULT 0
);

-- =======================
-- ÓRDENES
-- =======================
CREATE TABLE IF NOT EXISTS public.ordenes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo        text NOT NULL UNIQUE,
  estado        text NOT NULL DEFAULT 'agendada',
  subtotal      numeric(12,2) NOT NULL DEFAULT 0,
  total         numeric(12,2) NOT NULL DEFAULT 0,
  cerrada_at    timestamptz,
  tecnico_id    uuid REFERENCES public.tecnicos(id),
  creado_at     timestamptz NOT NULL DEFAULT now(),
  actualizado_at timestamptz NOT NULL DEFAULT now()
);

-- =======================
-- LÍNEAS DE ÓRDEN
-- =======================
CREATE TABLE IF NOT EXISTS public.orden_materiales (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id        uuid    NOT NULL REFERENCES public.ordenes(id)    ON DELETE CASCADE,
  material_id     integer NOT NULL REFERENCES public.materiales(id) ON DELETE RESTRICT,
  cantidad        numeric(12,3) NOT NULL DEFAULT 0,
  precio_unitario numeric(12,2) NOT NULL DEFAULT 0,
  -- requiere PostgreSQL 12+: columna generada
  total_calculado numeric(14,2) GENERATED ALWAYS AS (round(cantidad * precio_unitario, 2)) STORED
);
