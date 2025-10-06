-- migration 202510021940__add_usuarios.sql
CREATE TABLE IF NOT EXISTS usuarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_codigo TEXT UNIQUE NOT NULL,   -- opcional si ya existe relación
  estado TEXT NOT NULL CHECK (estado IN ('creado','instalado','desconectado','terminado')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_usuarios_estado ON usuarios(estado);
