-- backend/script/bootstrap_db_v2.sql
-- Idempotente: crea/ajusta vista kardex, regla de inserción, sync de stock, trigger,
-- constraint único limpio en orden_materiales e índices útiles.

SET client_min_messages TO WARNING;
SET search_path TO public;

-- =========================
-- 1) Vista 'kardex'
-- =========================
DROP VIEW IF EXISTS public.kardex;

CREATE VIEW public.kardex AS
SELECT
  m.id,
  m.tipo,
  m.almacen_origen_id,
  m.almacen_destino_id,
  COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
  m.material_id,
  -- etiqueta: sentido del movimiento visto por almacén
  CASE
    WHEN m.tipo = 'transferencia' AND m.almacen_destino_id IS NOT NULL THEN 'ingreso'
    WHEN m.tipo = 'transferencia' AND m.almacen_origen_id  IS NOT NULL THEN 'egreso'
    ELSE m.tipo
  END AS etiqueta,
  -- delta: signo aplicado por almacén
  CASE
    WHEN m.tipo IN ('ingreso','ajuste') AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
    WHEN m.tipo = 'egreso'               AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
    WHEN m.tipo = 'transferencia'        AND m.almacen_destino_id IS NOT NULL THEN  m.cantidad
    WHEN m.tipo = 'transferencia'        AND m.almacen_origen_id  IS NOT NULL THEN -m.cantidad
    ELSE 0
  END AS delta,
  m.cantidad,
  m.created_at
FROM public.movimientos m;

-- =========================
-- 2) Regla de inserción en 'kardex' -> tabla base 'movimientos'
-- =========================
DROP RULE IF EXISTS kardex_insert ON public.kardex;

CREATE RULE kardex_insert AS
ON INSERT TO public.kardex
DO INSTEAD
INSERT INTO public.movimientos (tipo, almacen_origen_id, almacen_destino_id, material_id, cantidad)
VALUES (
  CASE WHEN NEW.etiqueta = 'ingreso' THEN 'ingreso' ELSE 'egreso' END,
  CASE WHEN NEW.etiqueta = 'egreso'  THEN NEW.almacen_id ELSE NULL END,
  CASE WHEN NEW.etiqueta = 'ingreso' THEN NEW.almacen_id ELSE NULL END,
  NEW.material_id,
  GREATEST(ABS(COALESCE(NEW.cantidad, NEW.delta, 0)), 0)
);

-- =========================
-- 3) Función de sincronización de stock desde 'kardex'
--    (ajusta el JOIN si tienes mapeo almacen -> tecnico)
-- =========================
CREATE OR REPLACE FUNCTION public.sync_stock_desde_kardex(p_almacen uuid, p_material_id int)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_saldo int;
BEGIN
  SELECT COALESCE(SUM(delta), 0)
    INTO v_saldo
  FROM public.kardex
  WHERE almacen_id = p_almacen
    AND material_id = p_material_id;

  -- TODO: reemplazar tecnico_id=1 por join a tabla de mapeo almacen<->tecnico si aplica
  UPDATE public.inventario_tecnico_stock its
  SET stock = v_saldo
  WHERE its.material_id = p_material_id
    AND its.tecnico_id = 1;
END$$;

-- =========================
-- 4) Trigger que dispara recalculo de stock en movimientos
-- =========================
CREATE OR REPLACE FUNCTION public.trg_sync_stock_movimientos()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  a_old uuid; a_new uuid;
  m_old int;  m_new int;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.almacen_origen_id  IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(NEW.almacen_origen_id,  NEW.material_id);
    END IF;
    IF NEW.almacen_destino_id IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(NEW.almacen_destino_id, NEW.material_id);
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    a_old := OLD.almacen_origen_id;  a_new := NEW.almacen_origen_id;
    m_old := OLD.material_id;        m_new := NEW.material_id;

    -- Origen (antes y después)
    IF a_old IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(a_old, COALESCE(m_old, NEW.material_id));
    END IF;
    IF a_new IS NOT NULL AND (a_new <> a_old OR m_new <> m_old) THEN
      PERFORM public.sync_stock_desde_kardex(a_new, m_new);
    END IF;

    -- Destino (antes y después)
    a_old := OLD.almacen_destino_id; a_new := NEW.almacen_destino_id;
    IF a_old IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(a_old, COALESCE(m_old, NEW.material_id));
    END IF;
    IF a_new IS NOT NULL AND (a_new <> a_old OR m_new <> m_old) THEN
      PERFORM public.sync_stock_desde_kardex(a_new, m_new);
    END IF;

  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.almacen_origen_id  IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(OLD.almacen_origen_id,  OLD.material_id);
    END IF;
    IF OLD.almacen_destino_id IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(OLD.almacen_destino_id, OLD.material_id);
    END IF;
  END IF;

  RETURN NULL; -- AFTER trigger: retorno no usado
END$$;

DROP TRIGGER IF EXISTS trg_movs_sync_stock ON public.movimientos;

CREATE TRIGGER trg_movs_sync_stock
AFTER INSERT OR UPDATE OR DELETE ON public.movimientos
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_stock_movimientos();

-- =========================
-- 5) Constraint único limpio en orden_materiales
-- =========================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_orden_materiales_orden_id_material_id') THEN
    ALTER TABLE public.orden_materiales DROP CONSTRAINT uq_orden_materiales_orden_id_material_id;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ux_orden_materiales_orden_id_material_id') THEN
    DROP INDEX public.ux_orden_materiales_orden_id_material_id;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid='public.orden_materiales'::regclass
      AND conname='uq_orden_materiales_orden_material'
  ) THEN
    ALTER TABLE public.orden_materiales
      ADD CONSTRAINT uq_orden_materiales_orden_material UNIQUE (orden_id, material_id);
  END IF;
END$$;

-- =========================
-- 6) Índices para consultas por almacén/material y fecha
-- =========================
CREATE INDEX IF NOT EXISTS ix_movs_dest_mat_created
  ON public.movimientos (almacen_destino_id, material_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_movs_orig_mat_created
  ON public.movimientos (almacen_origen_id,  material_id, created_at DESC);
