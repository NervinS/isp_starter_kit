CREATE TABLE IF NOT EXISTS ordenes_evidencias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('foto','firma')),
  obj_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_oe_orden_id ON ordenes_evidencias(orden_id);
CREATE INDEX IF NOT EXISTS ix_oe_tipo ON ordenes_evidencias(tipo);
