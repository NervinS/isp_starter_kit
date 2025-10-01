-- script/migration_20251001_ventas_ordenes.sql
-- Idempotente: seguro de correr múltiples veces

-- ======================================================================
-- 1) Cols adicionales en VENTAS (recibos/contratos PDF) – si no existen
-- ======================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ventas' AND column_name='recibo_pdf_key'
  ) THEN
    ALTER TABLE public.ventas ADD COLUMN recibo_pdf_key text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ventas' AND column_name='contrato_pdf_key'
  ) THEN
    ALTER TABLE public.ventas ADD COLUMN contrato_pdf_key text;
  END IF;
END $$;


-- ======================================================================
-- 2) Tabla ORDENES – si no existe
-- ======================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='ordenes'
  ) THEN
    CREATE TABLE public.ordenes (
      id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      codigo           text NOT NULL UNIQUE,
      tipo             text NOT NULL,              -- INS | MAN | SUP | REP | ACT | BAJ ...
      estado           text NOT NULL,              -- pendiente | agendada | en_proceso | cerrada | cancelada | anulada
      agendado_para    date NULL,                  -- fecha programada (solo día)
      turno            text NULL,                  -- AM | PM | ...
      agendada_at      timestamp with time zone NULL,
      iniciada_at      timestamp with time zone NULL,
      cerrada_at       timestamp with time zone NULL,
      cancelada_at     timestamp with time zone NULL,
      motivo_cancelacion text NULL,                -- texto libre (o clave de catálogo)
      tecnico_id       uuid NULL,                  -- FK opcional a técnicos (otra tabla)
      venta_id         uuid NULL,                  -- FK a ventas
      CONSTRAINT fk_ordenes_venta
        FOREIGN KEY (venta_id) REFERENCES public.ventas(id)
        ON UPDATE CASCADE ON DELETE SET NULL
    );
  END IF;
END $$;


-- ======================================================================
-- 3) Índices operativos (idempotentes)
-- ======================================================================
-- Búsquedas por tipo/estado
CREATE INDEX IF NOT EXISTS idx_ordenes_tipo_estado
  ON public.ordenes (tipo, estado);

-- Por venta/tipo
CREATE INDEX IF NOT EXISTS idx_ordenes_venta_id_tipo
  ON public.ordenes (venta_id, tipo);

-- Por técnico/estado
CREATE INDEX IF NOT EXISTS idx_ordenes_tecnico_estado
  ON public.ordenes (tecnico_id, estado);

-- Aseguramos unicidad de código (por si la tabla existía sin UNIQUE)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname='public' AND indexname='ux_orden_codigo'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX ux_orden_codigo ON public.ordenes (codigo)';
  END IF;
END $$;


-- ======================================================================
-- 4) **Normalización**: garantizar a lo sumo UNA INS ACTIVA por venta
--    (anula duplicadas antiguas antes de crear el índice único parcial)
-- ======================================================================
DO $$
BEGIN
  -- Si la tabla existe, normalizamos.
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema='public' AND table_name='ordenes'
  ) THEN
    WITH ranked AS (
      SELECT
        id,
        venta_id,
        estado,
        -- timestamp de referencia (elige la más significativa disponible)
        COALESCE(agendada_at, iniciada_at, cerrada_at, cancelada_at) AS ts_ref,
        -- número al final del código (INS-000123 -> 123) a BIGINT para ordenar
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


-- ======================================================================
-- 5) Índice **parcial único** correcto para INS activas (no anuladas)
--    Reemplaza al índice antiguo ux_orden_unica_ins_venta
-- ======================================================================
-- Elimina el índice viejo si existe (el que no excluía anuladas)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname='public' AND indexname='ux_orden_unica_ins_venta'
  ) THEN
    EXECUTE 'DROP INDEX public.ux_orden_unica_ins_venta';
  END IF;
END $$;

-- Crea el índice parcial que sí ignora anuladas y NULLs en venta_id
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
