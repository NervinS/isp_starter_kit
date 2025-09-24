
CREATE TABLE auditoria (
  id uuid primary key default gen_random_uuid(),
  usuario_sistema_id uuid references usuarios_sistema(id),
  accion text not null,
  entidad text not null,
  entidad_id uuid,
  ip text,
  user_agent text,
  timestamp timestamptz not null default now(),
  detalle jsonb
);
