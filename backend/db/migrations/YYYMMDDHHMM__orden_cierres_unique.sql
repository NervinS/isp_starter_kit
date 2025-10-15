-- db/migrations/YYYMMDDHHMM__orden_cierres_unique.sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='uq_orden_cierres_orden'
  ) THEN
    CREATE UNIQUE INDEX uq_orden_cierres_orden ON public.orden_cierres(orden_id);
  END IF;
END $$;
