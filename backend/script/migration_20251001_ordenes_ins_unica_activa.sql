-- script/migration_20251001_ordenes_ins_unica_activa.sql
-- Objetivo: asegurar UNA sola INS activa por venta.
-- Idempotente: se puede ejecutar múltiples veces sin romper nada.

-- 1) Normalizar: si hay más de una INS por venta, dejar sólo UNA activa.
--    Criterio: prioriza (a) que no esté anulada, (b) la fecha "más significativa"
--    disponible (agendada/iniciada/cerrada/cancelada), (c) el número mayor del código,
--    y finalmente el id más reciente.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='ordenes'
  ) THEN
    WITH ranked AS (
      SELECT
        id,
        venta_id,
        estado,
        -- timestamp de referencia (la "más significativa" disponible)
        COALESCE(agendada_at, iniciada_at, cerrada_at, cancelada_at) AS ts_ref,
        -- toma SOLO los dígitos finales del código (INS-000002 -> 2) y castea a BIGINT
        NULLIF(SUBSTRING(codigo FROM '(\d+)$'), '')::bigint AS codigo_num,
        ROW_NUMBER() OVER (
          PARTITION BY venta_id
          ORDER BY
            (estado <> 'anulada')::int DESC,               -- primero activas
            COALESCE(agendada_at, iniciada_at, cerrada_at, cancelada_at) DESC NULLS LAST,
            NULLIF(SUBSTRING(codigo FROM '(\d+)$'), '')::bigint DESC NULLS LAST,
            id DESC
        ) AS rn
      FROM public.ordenes
      WHERE tipo = 'INS'
    )
    UPDATE public.ordenes o
       SET estado             = 'anulada',
           cancelada_at       = COALESCE(o.cancelada_at, now()),
           motivo_cancelacion = COALESCE(o.motivo_cancelacion, 'normalizacion: unica INS activa')
      FROM ranked r
     WHERE o.id = r.id
       AND r.rn > 1
       AND o.estado <> 'anulada';
  END IF;
END $$;

-- 2) Limpiar índice viejo (si existiera) que no excluía las anuladas.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname='public' AND indexname='ux_orden_unica_ins_venta'
  ) THEN
    EXECUTE 'DROP INDEX public.ux_orden_unica_ins_venta';
  END IF;
END $$;

-- 3) Crear índice parcial ÚNICO correcto: una sola INS activa (no anulada) por venta.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname='public' AND indexname='ux_orden_unica_ins_venta_activa'
  ) THEN
    EXECUTE $sql$
      CREATE UNIQUE INDEX ux_orden_unica_ins_venta_activa
        ON public.ordenes (venta_id)
       WHERE tipo = 'INS'
         AND estado <> 'anulada'
         AND venta_id IS NOT NULL
    $sql$;
  END IF;
END $$;
