
CREATE TABLE usuarios(
  id uuid primary key default gen_random_uuid(),
  codigo varchar(20) unique not null,
  tipo_cliente text check (tipo_cliente in ('hogar','corporativo')) not null,
  nombre varchar(120) not null,
  apellido varchar(120) not null,
  documento varchar(30) unique not null,
  email varchar(160),
  telefono varchar(30),
  estado text check (estado in ('nuevo','contratado','instalado','desconectado','terminado')) not null default 'nuevo',
  direccion text,
  barrio_id uuid references barrios(id),
  ciudad_id uuid references ciudades(id),
  geolat numeric(9,6),
  geolng numeric(9,6),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
CREATE INDEX idx_usuarios_busqueda ON usuarios (codigo, documento, apellido);
