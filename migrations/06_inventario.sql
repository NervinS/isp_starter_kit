
CREATE TABLE inventario_equipos (
  id uuid primary key default gen_random_uuid(),
  tipo text check (tipo in ('onu','router','stb')) not null,
  modelo text not null,
  serie text unique not null,
  mac text unique not null,
  estado text check (estado in ('nuevo','asignado','tecnico','usuario','defectuoso')) not null,
  ubicacion text check (ubicacion in ('almacen','tecnico','usuario')) not null,
  tecnico_id uuid references tecnicos(id),
  usuario_id uuid references usuarios(id),
  precinto varchar(30),
  created_at timestamptz default now()
);

CREATE TABLE inventario_materiales (
  id uuid primary key default gen_random_uuid(),
  descripcion text not null,
  unidad text not null default 'und',
  stock_actual numeric(12,2) not null default 0,
  stock_minimo numeric(12,2) not null default 0,
  activo boolean not null default true
);

CREATE TABLE mov_inventario (
  id uuid primary key default gen_random_uuid(),
  tipo text check (tipo in ('entrada','salida','traspaso')) not null,
  equipo_id uuid references inventario_equipos(id),
  material_id uuid references inventario_materiales(id),
  qty numeric(12,2) not null default 1,
  origen text,
  destino text,
  orden_id uuid references ordenes_servicio(id),
  notas text,
  created_at timestamptz default now()
);
