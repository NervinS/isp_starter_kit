
CREATE TABLE tickets (
  id uuid primary key default gen_random_uuid(),
  categoria text,
  prioridad text check (prioridad in ('baja','media','alta')) default 'media',
  sla_horas int default 48,
  estado text check (estado in ('abierto','en_proceso','resuelto','cerrado')) not null default 'abierto',
  usuario_id uuid references usuarios(id),
  operador_id uuid references agentes(id),
  agendado_para timestamptz,
  created_at timestamptz default now()
);

CREATE TABLE ordenes_servicio (
  id uuid primary key default gen_random_uuid(),
  tipo text check (tipo in ('instalacion','retiro','cambio_equipo','mantenimiento','traslado')) not null,
  ticket_id uuid references tickets(id),
  usuario_id uuid references usuarios(id),
  tecnico_id uuid references tecnicos(id),
  estado text check (estado in ('asignada','en_ruta','en_sitio','finalizada','rechazada')) not null default 'asignada',
  cita_inicio timestamptz,
  cita_fin timestamptz,
  geolat numeric(9,6),
  geolng numeric(9,6),
  firma_url text,
  cierre_notas text,
  created_at timestamptz default now()
);
