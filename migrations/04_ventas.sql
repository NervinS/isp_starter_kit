
CREATE TABLE ventas (
  id uuid primary key default gen_random_uuid(),
  vendedor_id uuid references agentes(id),
  usuario_pre_id uuid references usuarios(id),
  plan_id uuid references planes(id),
  adj_cedula_url text,
  adj_recibo_url text,
  firma_cliente_url text,
  contrato_pdf_url text,
  total numeric(12,2),
  estado text check (estado in ('borrador','pagado','anulada')) not null default 'borrador',
  created_at timestamptz default now()
);
