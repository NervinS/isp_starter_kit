
CREATE TABLE paises (id uuid primary key default gen_random_uuid(), nombre text not null);
CREATE TABLE ciudades (id uuid primary key default gen_random_uuid(), pais_id uuid references paises(id), nombre text not null);
CREATE TABLE barrios (id uuid primary key default gen_random_uuid(), ciudad_id uuid references ciudades(id), nombre text not null);
CREATE TABLE zonas (id uuid primary key default gen_random_uuid(), nombre text not null);

CREATE TABLE planes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  tipo text check (tipo in ('internet','tv')) not null,
  velocidad_mbps int not null default 0,
  activo boolean not null default true
);

CREATE TABLE tarifas (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references planes(id),
  moneda char(3) not null default 'COP',
  precio numeric(12,2) not null,
  impuesto_pct numeric(5,2) not null default 19
);

CREATE TABLE tecnicos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  zona text,
  activo boolean not null default true
);

CREATE TABLE agentes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  rol text not null default 'vendedor'
);
