BEGIN;

-- 1) enum para estado de conexión (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'usuario_estado_conexion') THEN
    CREATE TYPE usuario_estado_conexion AS ENUM ('conectado', 'desconectado');
  END IF;
END$$;

-- 2) columnas de auditoría (idempotente)
ALTER TABLE IF EXISTS usuarios
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- 3) columna de estado_conexion (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='usuarios' AND column_name='estado_conexion'
  ) THEN
    ALTER TABLE usuarios ADD COLUMN estado_conexion usuario_estado_conexion;
    -- valor por defecto razonable y backfill
    ALTER TABLE usuarios ALTER COLUMN estado_conexion SET DEFAULT 'conectado';
    UPDATE usuarios SET estado_conexion = COALESCE(estado_conexion, 'conectado');
  END IF;
END$$;

-- 4) trigger para updated_at (idempotente)
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgname='trg_usuarios_updated_at'
  ) THEN
    CREATE TRIGGER trg_usuarios_updated_at
    BEFORE UPDATE ON usuarios
    FOR EACH ROW
    EXECUTE PROCEDURE set_updated_at();
  END IF;
END$$;

COMMIT;
