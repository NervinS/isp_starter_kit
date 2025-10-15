BEGIN;

-- Evidencias (indexadas por orden, antes del cierre)
CREATE TABLE IF NOT EXISTS orden_evidencias (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id   UUID NOT NULL,
  kind       TEXT NOT NULL,
  key        TEXT NOT NULL,
  meta       JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_indexes
     WHERE indexname = 'ux_orden_evidencias_orden_kind_key'
  ) THEN
    CREATE UNIQUE INDEX ux_orden_evidencias_orden_kind_key
      ON orden_evidencias(orden_id, kind, key);
  END IF;
END $$;

-- Snapshot de cierre inmutable (uno por orden)
CREATE TABLE IF NOT EXISTS orden_cierres (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id        UUID NOT NULL UNIQUE,
  tipo            TEXT NOT NULL,
  payload_json    JSONB NOT NULL,
  evidencias_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  pdf_key         TEXT,
  checksum        TEXT,
  version         INT  NOT NULL DEFAULT 1,
  cerrado_por     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
