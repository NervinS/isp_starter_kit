-- 1) Ventas: columnas de evidencias y PDFs si faltan
ALTER TABLE IF EXISTS ventas
  ADD COLUMN IF NOT EXISTS cedula_img_key  text,
  ADD COLUMN IF NOT EXISTS recibo_img_key  text,
  ADD COLUMN IF NOT EXISTS firma_img_key   text,
  ADD COLUMN IF NOT EXISTS recibo_pdf_key  text,
  ADD COLUMN IF NOT EXISTS contrato_pdf_key text;

-- 2) Ordenes: link a venta/usuario y metadatos que ya consulta el código
ALTER TABLE IF EXISTS ordenes
  ADD COLUMN IF NOT EXISTS usuario_id uuid,
  ADD COLUMN IF NOT EXISTS venta_id   uuid,
  ADD COLUMN IF NOT EXISTS tecnico_id uuid,
  ADD COLUMN IF NOT EXISTS agendado_para timestamptz,
  ADD COLUMN IF NOT EXISTS turno text,
  ADD COLUMN IF NOT EXISTS iniciada_at timestamptz,
  ADD COLUMN IF NOT EXISTS cerrada_at  timestamptz;

-- Índices útiles
CREATE INDEX IF NOT EXISTS idx_ordenes_venta_id   ON ordenes(venta_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_usuario_id ON ordenes(usuario_id);
CREATE INDEX IF NOT EXISTS idx_ordenes_codigo     ON ordenes(codigo);
CREATE INDEX IF NOT EXISTS idx_ordenes_tipo       ON ordenes(tipo);

-- FKs suaves (omite ON DELETE si prefieres)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'ordenes_venta_fk'
  ) THEN
    ALTER TABLE ordenes
      ADD CONSTRAINT ordenes_venta_fk
      FOREIGN KEY (venta_id) REFERENCES ventas(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'ordenes_usuario_fk'
  ) THEN
    ALTER TABLE ordenes
      ADD CONSTRAINT ordenes_usuario_fk
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id);
  END IF;
END$$;

-- 3) Orden_materiales: lo usa TecnicosService en el cierre
CREATE TABLE IF NOT EXISTS orden_materiales (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id    uuid NOT NULL,
  material_id int  NOT NULL,
  cantidad    int  NOT NULL,
  descontado  boolean NOT NULL DEFAULT FALSE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (orden_id, material_id)
);
CREATE INDEX IF NOT EXISTS idx_om_orden_id ON orden_materiales(orden_id);

-- 4) Idempotencia genérica (ya la usa TecnicosService)
CREATE TABLE IF NOT EXISTS idem_requests(
  key text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 5) Idempotencia de pagos (si quieres registrar Idempotency-Key explícito)
CREATE TABLE IF NOT EXISTS venta_pagos_idem(
  idem_key text PRIMARY KEY,
  venta_id uuid NOT NULL REFERENCES ventas(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vpi_venta_id ON venta_pagos_idem(venta_id);
