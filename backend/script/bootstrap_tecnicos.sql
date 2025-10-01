-- Extensiones / tablas mínimas
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.tecnicos (
  id      serial PRIMARY KEY,
  codigo  text UNIQUE,
  nombre  text,
  activo  boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.materiales (
  id      serial PRIMARY KEY,
  codigo  text UNIQUE,
  nombre  text,
  unidad  text,
  activo  boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.inventario_tecnico_stock (
  tecnico_id  int  NOT NULL,
  material_id int  NOT NULL,
  cantidad    int  NOT NULL DEFAULT 0,
  stock       int  NOT NULL DEFAULT 0,
  PRIMARY KEY (tecnico_id, material_id)
);

CREATE TABLE IF NOT EXISTS public.movimientos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo text NOT NULL,
  almacen_origen_id uuid,
  almacen_destino_id uuid,
  material_id int NOT NULL,
  cantidad int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ordenes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo text UNIQUE NOT NULL,
  estado text NOT NULL DEFAULT 'pendiente',
  cerrada_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.orden_materiales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id uuid NOT NULL,
  material_id int NOT NULL,
  cantidad int NOT NULL DEFAULT 1,
  descontado boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- UNIQUE limpio: borra variantes antiguas y deja 1 consistente
ALTER TABLE public.orden_materiales
  DROP CONSTRAINT IF EXISTS uq_orden_materiales_orden_id_material_id;

DROP INDEX IF EXISTS public.ux_orden_materiales_orden_id_material_id;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.orden_materiales'::regclass
      AND conname='uq_orden_materiales_orden_material'
  ) THEN
    EXECUTE 'ALTER TABLE public.orden_materiales
             ADD CONSTRAINT uq_orden_materiales_orden_material UNIQUE (orden_id, material_id)';
  END IF;
END
$do$;

-- Trigger updated_at (idempotente)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_orden_materiales_updated_at ON public.orden_materiales;

CREATE TRIGGER trg_orden_materiales_updated_at
BEFORE UPDATE ON public.orden_materiales
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Índices de apoyo en movimientos
CREATE INDEX IF NOT EXISTS ix_movs_dest_mat_created
  ON public.movimientos (almacen_destino_id, material_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_movs_orig_mat_created
  ON public.movimientos (almacen_origen_id,  material_id, created_at DESC);
