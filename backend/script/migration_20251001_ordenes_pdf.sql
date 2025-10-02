CREATE TABLE IF NOT EXISTS ordenes_pdf (
  orden_id UUID PRIMARY KEY REFERENCES ordenes(id) ON DELETE CASCADE,
  acta_pdf_key TEXT,
  generado_at TIMESTAMPTZ DEFAULT now()
);
