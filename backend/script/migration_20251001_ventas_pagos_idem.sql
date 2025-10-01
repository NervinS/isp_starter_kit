-- 2025-10-01 migración: idempotencia de pagos de ventas (idempotente)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='venta_pagos_idem'
  ) THEN
    CREATE TABLE public.venta_pagos_idem (
      id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      idem_key          text NOT NULL,
      venta_id          uuid NOT NULL,
      created_at        timestamptz NOT NULL DEFAULT now()
    );
  END IF;
END$$;

-- Índice único por clave de idempotencia
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_venta_pagos_idem_key') THEN
    CREATE UNIQUE INDEX ux_venta_pagos_idem_key ON public.venta_pagos_idem (idem_key);
  END IF;
END$$;

-- Índice auxiliar para consultas por venta
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_venta_pagos_idem_venta') THEN
    CREATE INDEX ix_venta_pagos_idem_venta ON public.venta_pagos_idem (venta_id, created_at DESC);
  END IF;
END$$;
