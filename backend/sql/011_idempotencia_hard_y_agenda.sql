-- 011_idempotencia_hard_y_agenda.sql
-- Objetivo:
-- 1) Consolidar idempotencia HARD para cierre técnico.
-- 2) Asegurar columnas de agenda (fecha/turno) para endpoints HTTP.
-- Seguro para re-ejecución (IF NOT EXISTS / ALTER ... IF NOT EXISTS).

BEGIN;

-- 1) Tabla de idempotencia de cierres (si 010 ya existe, esto asegura estructura + índices)
CREATE TABLE IF NOT EXISTS public.orden_cierres_idem (
  id                BIGSERIAL PRIMARY KEY,
  orden_codigo      VARCHAR(32) NOT NULL,
  payload_hash      VARCHAR(64) NOT NULL,
  idempotency_key   VARCHAR(128),
  first_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  response_status   INT,
  response_body     JSONB,
  CONSTRAINT ux_oci_orden_payload UNIQUE (orden_codigo, payload_hash)
);

-- Índice adicional por key (no único, varias órdenes podrían usar misma key)
CREATE INDEX IF NOT EXISTS idx_oci_key ON public.orden_cierres_idem (idempotency_key);

-- 2) Asegurar columnas de agenda en ordenes
ALTER TABLE public.ordenes
  ADD COLUMN IF NOT EXISTS agenda_fecha DATE,
  ADD COLUMN IF NOT EXISTS agenda_turno VARCHAR(16),
  ADD COLUMN IF NOT EXISTS tecnico_id UUID;

-- 3) Integridad referencial de tecnico_id si la tabla tecnicos existe
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'tecnicos'
  ) THEN
    BEGIN
      ALTER TABLE public.ordenes
        ADD CONSTRAINT fk_ordenes_tecnico
        FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id)
        ON UPDATE CASCADE ON DELETE SET NULL;
    EXCEPTION WHEN duplicate_object THEN
      -- constraint ya existe
      NULL;
    END;
  END IF;
END$$;

COMMIT;
