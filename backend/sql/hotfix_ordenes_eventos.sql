-- sql/hotfix_ordenes_eventos.sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='ordenes_eventos' AND column_name='payload') THEN
    ALTER TABLE ordenes_eventos ADD COLUMN payload jsonb NOT NULL DEFAULT '{}'::jsonb;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ix_ordenes_eventos_orden') THEN
    CREATE INDEX ix_ordenes_eventos_orden ON ordenes_eventos(codigo, created_at);
  END IF;
END$$;
