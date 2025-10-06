-- 20251003_0200_add_pdf_cols.sql
ALTER TABLE ordenes
  ADD COLUMN IF NOT EXISTS pdf_url  text,
  ADD COLUMN IF NOT EXISTS pdf_key  text,
  ADD COLUMN IF NOT EXISTS firma_key text;