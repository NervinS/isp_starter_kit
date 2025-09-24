
CREATE TABLE roles (id uuid primary key default gen_random_uuid(), nombre text unique not null);
CREATE TABLE permisos (id uuid primary key default gen_random_uuid(), recurso text not null, accion text not null);
CREATE TABLE rol_permisos (rol_id uuid references roles(id), permiso_id uuid references permisos(id), primary key(rol_id, permiso_id));
CREATE TABLE usuarios_sistema (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  password_hash text not null,
  nombre text,
  activo boolean not null default true
);
CREATE TABLE usuario_roles (usuario_id uuid references usuarios_sistema(id), rol_id uuid references roles(id), primary key(usuario_id, rol_id));
