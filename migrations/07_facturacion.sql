
CREATE TABLE facturas(
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references usuarios(id),
  numero_fiscal varchar(30) unique not null,
  periodo char(7) not null,
  fecha_emision date not null,
  fecha_vencimiento date not null,
  subtotal numeric(12,2) not null,
  impuestos numeric(12,2) not null,
  descuentos numeric(12,2) not null default 0,
  total numeric(12,2) not null,
  estado text check (estado in ('emitida','pagada','vencida','anulada')) not null default 'emitida',
  pdf_url text,
  created_at timestamptz default now()
);
CREATE INDEX idx_facturas_usuario_periodo ON facturas(usuario_id, periodo);

CREATE TABLE factura_detalle(
  id uuid primary key default gen_random_uuid(),
  factura_id uuid references facturas(id),
  concepto text not null,
  cantidad numeric(12,2) not null default 1,
  precio_unit numeric(12,2) not null,
  total_linea numeric(12,2) not null,
  plan_id uuid references planes(id),
  servicio_id uuid
);

CREATE TABLE pagos(
  id uuid primary key default gen_random_uuid(),
  factura_id uuid references facturas(id),
  usuario_id uuid references usuarios(id),
  medio text check (medio in ('efectivo','transferencia','pasarela')),
  referencia text,
  monto numeric(12,2) not null,
  fecha timestamptz not null default now(),
  conciliado boolean not null default false
);

CREATE TABLE notas_credito(
  id uuid primary key default gen_random_uuid(),
  factura_id uuid references facturas(id),
  motivo text not null,
  monto numeric(12,2) not null,
  fecha timestamptz not null default now(),
  admin_id uuid,
  audit_json jsonb
);

CREATE TABLE cierres_contables(
  id uuid primary key default gen_random_uuid(),
  periodo char(7) unique not null,
  cerrado_por uuid,
  cerrado_en timestamptz default now(),
  reabierto_por uuid,
  reabierto_en timestamptz
);
