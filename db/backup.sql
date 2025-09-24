--
-- PostgreSQL database dump
--

\restrict Bl7CMsidO5aXZQytZBNEijzGARPHcRcKhdQKwKCx9VtlkyHFMJCY5t55wua5IOK

-- Dumped from database version 15.13 (Debian 15.13-1.pgdg130+1)
-- Dumped by pg_dump version 15.14 (Ubuntu 15.14-1.pgdg22.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: cliente_estado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cliente_estado AS ENUM (
    'nuevo',
    'contratado',
    'instalado',
    'desconectado',
    'terminado'
);


--
-- Name: usuario_estado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.usuario_estado AS ENUM (
    'nuevo',
    'contratado',
    'instalado',
    'desconectado',
    'terminado'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agentes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agentes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL,
    rol text DEFAULT 'vendedor'::text NOT NULL
);


--
-- Name: app_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username character varying(50) NOT NULL,
    pass_hash text NOT NULL,
    roles text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_sistema_id uuid,
    accion text NOT NULL,
    entidad text NOT NULL,
    entidad_id uuid,
    ip text,
    user_agent text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    detalle jsonb
);


--
-- Name: barrios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.barrios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ciudad_id uuid,
    nombre text NOT NULL
);


--
-- Name: cierres_contables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cierres_contables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    periodo character(7) NOT NULL,
    cerrado_por uuid,
    cerrado_en timestamp with time zone DEFAULT now(),
    reabierto_por uuid,
    reabierto_en timestamp with time zone
);


--
-- Name: ciudades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ciudades (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pais_id uuid,
    nombre text NOT NULL
);


--
-- Name: evidencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evidencias (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    orden_id uuid NOT NULL,
    tipo character varying(16) NOT NULL,
    object_key character varying(255) NOT NULL,
    mime character varying(80),
    size integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: factura_detalle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.factura_detalle (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    factura_id uuid,
    concepto text NOT NULL,
    cantidad numeric(12,2) DEFAULT 1 NOT NULL,
    precio_unit numeric(12,2) NOT NULL,
    total_linea numeric(12,2) NOT NULL,
    plan_id uuid,
    servicio_id uuid
);


--
-- Name: facturas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facturas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    numero_fiscal character varying(30) NOT NULL,
    periodo character(7) NOT NULL,
    fecha_emision date NOT NULL,
    fecha_vencimiento date NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    impuestos numeric(12,2) NOT NULL,
    descuentos numeric(12,2) DEFAULT 0 NOT NULL,
    total numeric(12,2) NOT NULL,
    estado text DEFAULT 'emitida'::text NOT NULL,
    pdf_url text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT facturas_estado_check CHECK ((estado = ANY (ARRAY['emitida'::text, 'pagada'::text, 'vencida'::text, 'anulada'::text])))
);


--
-- Name: inventario_equipos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_equipos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    modelo text NOT NULL,
    serie text NOT NULL,
    mac text NOT NULL,
    estado text NOT NULL,
    ubicacion text NOT NULL,
    tecnico_id uuid,
    usuario_id uuid,
    precinto character varying(30),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT inventario_equipos_estado_check CHECK ((estado = ANY (ARRAY['nuevo'::text, 'asignado'::text, 'tecnico'::text, 'usuario'::text, 'defectuoso'::text]))),
    CONSTRAINT inventario_equipos_tipo_check CHECK ((tipo = ANY (ARRAY['onu'::text, 'router'::text, 'stb'::text]))),
    CONSTRAINT inventario_equipos_ubicacion_check CHECK ((ubicacion = ANY (ARRAY['almacen'::text, 'tecnico'::text, 'usuario'::text])))
);


--
-- Name: inventario_materiales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventario_materiales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    descripcion text NOT NULL,
    unidad text DEFAULT 'und'::text NOT NULL,
    stock_actual numeric(12,2) DEFAULT 0 NOT NULL,
    stock_minimo numeric(12,2) DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: mov_inventario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mov_inventario (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    equipo_id uuid,
    material_id uuid,
    qty numeric(12,2) DEFAULT 1 NOT NULL,
    origen text,
    destino text,
    orden_id uuid,
    notas text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT mov_inventario_tipo_check CHECK ((tipo = ANY (ARRAY['entrada'::text, 'salida'::text, 'traspaso'::text])))
);


--
-- Name: municipios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.municipios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true
);


--
-- Name: notas_credito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notas_credito (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    factura_id uuid,
    motivo text NOT NULL,
    monto numeric(12,2) NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    admin_id uuid,
    audit_json jsonb
);


--
-- Name: ordenes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ordenes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo character varying(20) NOT NULL,
    venta_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    tipo character varying(30) DEFAULT 'instalacion'::character varying NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    lat double precision,
    lng double precision,
    onu_serial character varying(40),
    vlan character varying(20),
    precinto character varying(40),
    cerrada_por character varying(80),
    cerrada_at timestamp with time zone
);


--
-- Name: ordenes_servicio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ordenes_servicio (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    ticket_id uuid,
    usuario_id uuid,
    tecnico_id uuid,
    estado text DEFAULT 'asignada'::text NOT NULL,
    cita_inicio timestamp with time zone,
    cita_fin timestamp with time zone,
    geolat numeric(9,6),
    geolng numeric(9,6),
    firma_url text,
    cierre_notas text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT ordenes_servicio_estado_check CHECK ((estado = ANY (ARRAY['asignada'::text, 'en_ruta'::text, 'en_sitio'::text, 'finalizada'::text, 'rechazada'::text]))),
    CONSTRAINT ordenes_servicio_tipo_check CHECK ((tipo = ANY (ARRAY['instalacion'::text, 'retiro'::text, 'cambio_equipo'::text, 'mantenimiento'::text, 'traslado'::text])))
);


--
-- Name: pagos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    factura_id uuid,
    usuario_id uuid,
    medio text,
    referencia text,
    monto numeric(12,2) NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    conciliado boolean DEFAULT false NOT NULL,
    CONSTRAINT pagos_medio_check CHECK ((medio = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'pasarela'::text])))
);


--
-- Name: paises; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.paises (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL
);


--
-- Name: permisos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permisos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recurso text NOT NULL,
    accion text NOT NULL
);


--
-- Name: planes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL,
    tipo text DEFAULT 'internet'::text NOT NULL,
    velocidad_mbps integer DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    codigo text NOT NULL,
    vel_mbps integer DEFAULT 0 NOT NULL,
    alta_costo numeric(12,2) DEFAULT 0 NOT NULL,
    mensual numeric(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT planes_tipo_check CHECK ((tipo = ANY (ARRAY['internet'::text, 'tv'::text])))
);


--
-- Name: rol_permisos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rol_permisos (
    rol_id uuid NOT NULL,
    permiso_id uuid NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL
);


--
-- Name: sectores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sectores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    municipio_codigo text NOT NULL,
    zona text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    CONSTRAINT sectores_zona_check CHECK ((zona = ANY (ARRAY['BARRIO'::text, 'CONJUNTO'::text, 'COMUNA'::text])))
);


--
-- Name: smartolt_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.smartolt_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    endpoint text NOT NULL,
    metodo text NOT NULL,
    request_id uuid NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    payload_redacted jsonb,
    status_code integer,
    response_trunc jsonb,
    error_text text,
    retry_count integer DEFAULT 0,
    correlacion text
);


--
-- Name: tarifas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tarifas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    moneda character(3) DEFAULT 'COP'::bpchar NOT NULL,
    precio numeric(12,2) NOT NULL,
    impuesto_pct numeric(5,2) DEFAULT 19 NOT NULL
);


--
-- Name: tecnicos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tecnicos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL,
    zona text,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    categoria text,
    prioridad text DEFAULT 'media'::text,
    sla_horas integer DEFAULT 48,
    estado text DEFAULT 'abierto'::text NOT NULL,
    usuario_id uuid,
    operador_id uuid,
    agendado_para timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT tickets_estado_check CHECK ((estado = ANY (ARRAY['abierto'::text, 'en_proceso'::text, 'resuelto'::text, 'cerrado'::text]))),
    CONSTRAINT tickets_prioridad_check CHECK ((prioridad = ANY (ARRAY['baja'::text, 'media'::text, 'alta'::text])))
);


--
-- Name: usuario_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_roles (
    usuario_id uuid NOT NULL,
    rol_id uuid NOT NULL
);


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo character varying(20) NOT NULL,
    tipo_cliente text NOT NULL,
    nombre character varying(120) NOT NULL,
    apellido character varying(120) NOT NULL,
    documento character varying(30) NOT NULL,
    email character varying(160),
    telefono character varying(30),
    estado text DEFAULT 'nuevo'::text NOT NULL,
    direccion text,
    barrio_id uuid,
    ciudad_id uuid,
    geolat numeric(9,6),
    geolng numeric(9,6),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    municipio_id uuid,
    zona text,
    barrio_conjunto text,
    via text,
    nombre_via text,
    indicador text,
    orientacion text,
    numero_casa text,
    saldo numeric(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT usuarios_estado_check CHECK ((estado = ANY (ARRAY['nuevo'::text, 'contratado'::text, 'instalado'::text, 'desconectado'::text, 'terminado'::text]))),
    CONSTRAINT usuarios_tipo_cliente_check CHECK ((tipo_cliente = ANY (ARRAY['hogar'::text, 'corporativo'::text])))
);


--
-- Name: usuarios_sistema; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios_sistema (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    nombre text,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: ventas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ventas (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo character varying(20) NOT NULL,
    usuario_id uuid,
    cliente_nombre character varying(120) NOT NULL,
    cliente_apellido character varying(120) NOT NULL,
    documento character varying(30) NOT NULL,
    total numeric(12,2) DEFAULT 0 NOT NULL,
    estado character varying(20) DEFAULT 'creada'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    plan_codigo text,
    incluye_tv boolean DEFAULT false NOT NULL,
    plan_nombre text,
    plan_vel_mbps integer,
    plan_alta numeric(12,2) DEFAULT 0,
    plan_mensual numeric(12,2) DEFAULT 0,
    alta_costo numeric(12,2) DEFAULT 0,
    mensual_internet numeric(12,2) DEFAULT 0,
    mensual_tv numeric(12,2) DEFAULT 0,
    mensual_total numeric(12,2) DEFAULT 0,
    recibo_pdf_key text,
    contrato_pdf_key text,
    recibo_img_key text,
    cedula_img_key text,
    firma_img_key text
);


--
-- Name: ventas_codigo_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ventas_codigo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


--
-- Name: zonas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zonas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL
);


--
-- Data for Name: agentes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agentes (id, nombre, rol) FROM stdin;
d4419d5a-0ccb-4553-8ac4-b2253dfe1a15	María Vendedora	vendedor
\.


--
-- Data for Name: app_users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_users (id, username, pass_hash, roles, created_at) FROM stdin;
f4ede5f3-ac51-4c0c-afaa-446cf858cc6d	admin	$argon2id$v=19$m=65536,t=3,p=4$gqsBgR2OvU4/LllKu5QAPw$WxqkMvcfqD2ATtGIbUDIIpzWswb9EI8h2I9uxohR7ig	{admin}	2025-08-19 14:42:31.467091-05
e547de3e-0d24-42dc-acde-16e9cadb5453	tec1	$argon2id$v=19$m=65536,t=3,p=4$mE+ZgjHWi6Y/bCG6qA2HJg$ey9MwJZaa2jsZHCOcwAFQb/QZGnNAPOsa5NkLzVigxI	{tecnico}	2025-08-19 14:42:31.467091-05
8250c47d-dc57-447e-80a5-277b847e57d0	ventas	$argon2id$v=19$m=65536,t=3,p=4$Q/kJonjwHDuCimATEskqMg$kF1w2jd3B0vVNftuTqhbWL/xHnbUlK14DdirmuU9wV8	{ventas}	2025-08-19 14:42:31.467091-05
90486692-d66b-438f-8ed0-73e816a4de55	ven1	$argon2id$v=19$m=65536,t=3,p=4$U2eSxzRsW17p8hNefV1o1w$iEoGPyIecchkZbA9J2jsCKAl4OcQIyOU9Jk2OtQUC5Q	{ventas}	2025-08-27 11:08:46.663087-05
\.


--
-- Data for Name: auditoria; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditoria (id, usuario_sistema_id, accion, entidad, entidad_id, ip, user_agent, "timestamp", detalle) FROM stdin;
\.


--
-- Data for Name: barrios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.barrios (id, ciudad_id, nombre) FROM stdin;
0189d295-f056-4379-b944-870c43ad10f0	28ab11ff-ac48-4016-9a28-9ed3e0a804ce	Centro
560cbde1-09e3-490b-a94a-668274ef102b	28ab11ff-ac48-4016-9a28-9ed3e0a804ce	Sur
575d82ef-f615-4762-bbcd-80b29860882e	28ab11ff-ac48-4016-9a28-9ed3e0a804ce	Norte
\.


--
-- Data for Name: cierres_contables; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cierres_contables (id, periodo, cerrado_por, cerrado_en, reabierto_por, reabierto_en) FROM stdin;
\.


--
-- Data for Name: ciudades; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ciudades (id, pais_id, nombre) FROM stdin;
28ab11ff-ac48-4016-9a28-9ed3e0a804ce	89e323c1-3b1e-4148-a52a-a04c9d4f9173	Medellín
\.


--
-- Data for Name: evidencias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.evidencias (id, orden_id, tipo, object_key, mime, size, created_at) FROM stdin;
e7d9b56d-6915-4dc1-80aa-c3626d7f3741	de9a712c-ad6b-490a-938b-7269cb38c56d	foto	ordenes/ORD-000009/1755141213358-j1elu3.jpg	image/jpeg	42170	2025-08-13 22:13:33.369221-05
a2a06036-1580-4318-bb37-4c1b29a1abb2	de9a712c-ad6b-490a-938b-7269cb38c56d	firma	ordenes/ORD-000009/1755141213382-2twt1c.png	image/png	21353	2025-08-13 22:13:33.389752-05
9bb899f3-ae77-4a07-b2dd-2cce6f865122	e4161186-e93c-481e-b39c-4cfc166ccd3d	foto	ordenes/ORD-000010/1755141398068-tzlxy7.jpg	image/jpeg	42170	2025-08-13 22:16:38.077983-05
cf430bdf-aea7-4e89-8cfd-92179aceab26	e4161186-e93c-481e-b39c-4cfc166ccd3d	firma	ordenes/ORD-000010/1755141398086-n2hl10.png	image/png	21353	2025-08-13 22:16:38.094572-05
6e50f88e-ee93-447b-a7f8-992f699d5f7a	2ee14414-c2a8-42e0-a16c-24df7706f999	foto	ordenes/ORD-000012/1755198504877-ufqrq7.jpg	image/jpeg	6098	2025-08-14 14:08:24.88691-05
673c9e78-cd89-4150-a03d-6a49d19a79e5	2ee14414-c2a8-42e0-a16c-24df7706f999	firma	ordenes/ORD-000012/1755198504893-chwfeq.png	image/png	5981	2025-08-14 14:08:24.899373-05
d4d6b09c-586c-40c6-923b-3b059d4c1a3a	d8de0b1a-9b1b-49ad-bff6-0ac1c2a02cf5	foto	ordenes/ORD-000015/1755205172843-3timw.jpg	image/jpeg	9252	2025-08-14 15:59:32.871299-05
b48bba32-7ccb-46e4-8c94-d21365408b53	d8de0b1a-9b1b-49ad-bff6-0ac1c2a02cf5	firma	ordenes/ORD-000015/1755205172876-6trt9.png	image/png	4995	2025-08-14 15:59:32.88491-05
bb32d3bb-c5fb-4355-8f72-0473a229a163	181df4e0-3d4c-47e6-81fb-a74963e4afc4	foto	ordenes/ORD-000016/1755621353516-rs6t4.jpg	image/jpeg	71773	2025-08-19 11:35:53.541679-05
8d6e9317-80f1-4397-ad8a-ab9ebfccf9f6	181df4e0-3d4c-47e6-81fb-a74963e4afc4	firma	ordenes/ORD-000016/1755621353546-ganka.png	image/png	6376	2025-08-19 11:35:53.55363-05
6918e909-268c-4ca0-91e4-c0d824ad76c2	0a17e5ef-f4d3-44ff-a60b-e04cc0aed4f5	foto	ordenes/ORD-000017/1755622704878-lkgwm.jpg	image/jpeg	42170	2025-08-19 11:58:24.887622-05
863d7ff1-65ef-4a80-b097-25de0253a810	0a17e5ef-f4d3-44ff-a60b-e04cc0aed4f5	firma	ordenes/ORD-000017/1755622704890-cqcix.png	image/png	21353	2025-08-19 11:58:24.901449-05
1dae4636-4c49-47e9-a126-356c36ae00db	1959794e-70f1-42df-b7bf-e4cd014d47ac	foto	ordenes/ORD-000018/1755622734570-88r0d.jpg	image/jpeg	42170	2025-08-19 11:58:54.579492-05
2176deac-6ab3-464c-b610-96f53ff94ecf	1959794e-70f1-42df-b7bf-e4cd014d47ac	firma	ordenes/ORD-000018/1755622734582-7md5b.png	image/png	21353	2025-08-19 11:58:54.589776-05
9c180fd4-d8cf-4365-b3ca-363d53c3c95c	352854c3-27b6-459e-be3b-210556dff3ef	foto	ordenes/ORD-000019/1755706513071-ca9tr.jpg	image/jpeg	42170	2025-08-20 11:15:13.095612-05
6aa8d685-3972-4705-b6b1-60239894957e	352854c3-27b6-459e-be3b-210556dff3ef	firma	ordenes/ORD-000019/1755706513100-id4v6.png	image/png	21353	2025-08-20 11:15:13.108517-05
c387e144-8525-48a3-ad48-867d91ad267e	12c75d88-c1fe-4895-beae-faed56e493e7	foto	ordenes/ORD-000022/1755787758529-few8v.png	image/png	68	2025-08-21 09:49:18.54965-05
5cee5d24-344d-4482-908a-1cec084b4d14	12c75d88-c1fe-4895-beae-faed56e493e7	foto	ordenes/ORD-000022/1755787758553-7qenr.png	image/png	68	2025-08-21 09:49:18.560022-05
53137f35-0d75-4b8b-a8cb-dcecbc078a0a	12c75d88-c1fe-4895-beae-faed56e493e7	firma	ordenes/ORD-000022/1755787758562-tygmb.png	image/png	68	2025-08-21 09:49:18.569448-05
b300d485-e6be-4528-bbcd-14a11d88d067	29e1af19-9966-4ca7-a560-725dbf7b1b98	foto	ordenes/ORD-000023/1755790586929-me9qn.png	image/png	68	2025-08-21 10:36:26.939696-05
38996724-2b91-44f4-abd2-f7800ddc9de4	29e1af19-9966-4ca7-a560-725dbf7b1b98	foto	ordenes/ORD-000023/1755790586942-88kz0.png	image/png	68	2025-08-21 10:36:26.950658-05
bc67bceb-4bff-46e0-98e1-3be0791071a9	29e1af19-9966-4ca7-a560-725dbf7b1b98	firma	ordenes/ORD-000023/1755790586953-idyuu.png	image/png	68	2025-08-21 10:36:26.959337-05
76da4c04-827e-460a-8ea6-7be9ad83a4ae	0dfc2bf7-e9c1-4c70-ab7d-7735d54e519a	foto	ordenes/ORD-000025/1755807002995-nr6o9.png	image/png	68	2025-08-21 15:10:03.019526-05
82319707-2300-4447-a012-819aa372d812	0dfc2bf7-e9c1-4c70-ab7d-7735d54e519a	foto	ordenes/ORD-000025/1755807003025-dsfc3.png	image/png	68	2025-08-21 15:10:03.033325-05
ec2f8259-6a89-4b6e-b71e-e548b9dec5f9	0dfc2bf7-e9c1-4c70-ab7d-7735d54e519a	firma	ordenes/ORD-000025/1755807003036-gxhe1.png	image/png	68	2025-08-21 15:10:03.044216-05
2594b38f-a796-4187-90fe-9d62845c9ecf	9859bb40-a126-45c4-8cfc-c2a67338f1c1	foto	ordenes/ORD-000024/1756324655124-sb9mw.jpg	image/jpeg	26	2025-08-27 14:57:35.148432-05
78d148fc-26bb-4fee-b416-05ab61a6bbbf	9859bb40-a126-45c4-8cfc-c2a67338f1c1	firma	ordenes/ORD-000024/1756324655153-5300k.png	image/png	67	2025-08-27 14:57:35.160307-05
f76a04d0-d4e6-4908-9ea0-ce042bd72b47	54a5ef8a-e623-4e69-b359-c0e912c39a5a	foto	ordenes/ORD-000026/1756324692807-u7ovj.jpg	image/jpeg	71773	2025-08-27 14:58:12.818176-05
40c6b1b5-3e37-45a9-b9a6-f894b56682dc	54a5ef8a-e623-4e69-b359-c0e912c39a5a	firma	ordenes/ORD-000026/1756324692822-m0g4t.png	image/png	6357	2025-08-27 14:58:12.831877-05
fdfc4d18-8f67-40b7-b071-564f5ba6fccd	54a5ef8a-e623-4e69-b359-c0e912c39a5a	foto	ordenes/ORD-000026/1756324702112-p4c5w.jpg	image/jpeg	71773	2025-08-27 14:58:22.122315-05
6459d43b-6fbf-4aa6-a8de-2382db087f04	54a5ef8a-e623-4e69-b359-c0e912c39a5a	firma	ordenes/ORD-000026/1756324702126-hi7n2.png	image/png	6357	2025-08-27 14:58:22.133705-05
1db356e1-8b58-47d3-904b-59308b2fca9b	13510fea-b372-489e-8d64-be495fb525cf	foto	ordenes/ORD-000027/1756324786748-5j6x5.jpg	image/jpeg	6098	2025-08-27 14:59:46.757172-05
6c9419a2-94f0-4b3e-bb03-a9e61b3f1623	13510fea-b372-489e-8d64-be495fb525cf	firma	ordenes/ORD-000027/1756324786760-qidvf.png	image/png	6150	2025-08-27 14:59:46.768163-05
5cf7d876-3cf7-477e-bb60-5feb03114114	68a72c38-b7c2-4608-8df6-4ce14802f7f7	foto	ordenes/ORD-000028/1756324933968-l2eul.jpg	image/jpeg	9252	2025-08-27 15:02:13.978726-05
98753318-c8d3-4dd9-a1ee-78a01465946f	68a72c38-b7c2-4608-8df6-4ce14802f7f7	firma	ordenes/ORD-000028/1756324933983-to0jy.png	image/png	4535	2025-08-27 15:02:13.990421-05
d01e8f74-0e35-40f1-a947-3dc27cda3b2a	6922f2fe-fff6-47f8-a30d-cbf95ba8f83f	foto	ordenes/ORD-000029/1756331381068-orv5e.jpg	image/jpeg	9252	2025-08-27 16:49:41.095992-05
b71edf9b-d597-455d-918c-5e262e924f48	6922f2fe-fff6-47f8-a30d-cbf95ba8f83f	firma	ordenes/ORD-000029/1756331381101-lh4n7.png	image/png	6865	2025-08-27 16:49:41.110611-05
214a6c5d-070d-4499-88e5-c9a0ff300d7d	3ff8ca7d-0397-443a-99a8-6b0a6b233e6d	foto	ordenes/ORD-000030/1756332370614-v7nui.jpg	image/jpeg	85965	2025-08-27 17:06:10.640232-05
20d0ec93-1e27-487b-ba3e-c3884d4e3b8a	3ff8ca7d-0397-443a-99a8-6b0a6b233e6d	firma	ordenes/ORD-000030/1756332370645-moava.png	image/png	4934	2025-08-27 17:06:10.653748-05
fe25411a-1824-4cc2-92a8-53bd1aad8d59	1bf6e3c7-ddee-4920-a8e5-736ced3c0e42	foto	ordenes/ORD-000031/1756395064510-esp2p.jpg	image/jpeg	9252	2025-08-28 10:31:04.53257-05
7ffe983b-9fe7-4254-bc61-dbfdd438b386	1bf6e3c7-ddee-4920-a8e5-736ced3c0e42	firma	ordenes/ORD-000031/1756395064537-1439z.png	image/png	5562	2025-08-28 10:31:04.544402-05
365ee808-da5b-476a-bd47-9933004db035	77675493-e941-4983-9b11-b8a063c5f042	foto	ordenes/ORD-000032/1756395192678-unr0i.jpg	image/jpeg	6098	2025-08-28 10:33:12.690459-05
8320d7e5-2bfc-4427-81a6-70b10596177b	77675493-e941-4983-9b11-b8a063c5f042	firma	ordenes/ORD-000032/1756395192696-jdd60.png	image/png	5326	2025-08-28 10:33:12.707093-05
f8acf9ad-ed43-4a7f-b105-41ea84326215	376d4d5b-07ea-40d6-8e30-14c57ec9bf87	foto	ordenes/ORD-000042/1756411545064-z2he3.jpg	image/jpeg	6098	2025-08-28 15:05:45.086611-05
c1d47993-c9a3-4209-b0c2-eb57a60e960e	376d4d5b-07ea-40d6-8e30-14c57ec9bf87	firma	ordenes/ORD-000042/1756411545090-asuyp.png	image/png	4289	2025-08-28 15:05:45.098411-05
cac5a5dd-9a64-41c7-9a91-1c490b460d8c	780c046d-58cc-4d15-9ad9-05ec63d282c4	foto	ordenes/ORD-000041/1756411558617-muqu8.jpg	image/jpeg	85965	2025-08-28 15:05:58.628222-05
8303657c-b354-42d3-af7d-247e9cc94148	780c046d-58cc-4d15-9ad9-05ec63d282c4	firma	ordenes/ORD-000041/1756411558631-tvyme.png	image/png	4662	2025-08-28 15:05:58.640898-05
168d6a21-3b88-4b70-bdcc-abb4be3398c5	cb8febbe-6ab8-43da-8a35-59e0d6708cdd	foto	ordenes/ORD-000040/1756411580276-g30sz.jpg	image/jpeg	9252	2025-08-28 15:06:20.285881-05
62c74b26-e03f-4556-a8a8-82836dfbc2b3	cb8febbe-6ab8-43da-8a35-59e0d6708cdd	foto	ordenes/ORD-000040/1756411580289-s7pkd.jpg	image/jpeg	6098	2025-08-28 15:06:20.296867-05
9b38378e-64a6-4a48-a6ca-1866582b08bf	cb8febbe-6ab8-43da-8a35-59e0d6708cdd	firma	ordenes/ORD-000040/1756411580300-g7bzt.png	image/png	4592	2025-08-28 15:06:20.306614-05
ba581170-da12-4f54-bde0-f706d441f57b	a40fff73-0cb2-427a-bb9a-b4946d2e65f7	foto	ordenes/ORD-000039/1756411596556-5plrg.jpg	image/jpeg	44939	2025-08-28 15:06:36.567221-05
b8686317-1150-4113-afcb-6ecf16189e84	a40fff73-0cb2-427a-bb9a-b4946d2e65f7	firma	ordenes/ORD-000039/1756411596570-95vl0.png	image/png	4273	2025-08-28 15:06:36.578737-05
4f44f133-a437-47e8-a406-1dc507206372	07f1001c-0eab-4838-b834-e487e501f0df	foto	ordenes/ORD-000038/1756411629029-ic0ax.jpg	image/jpeg	9252	2025-08-28 15:07:09.037822-05
1fb46ff8-6cdb-4707-966a-e1bae63a6fa7	07f1001c-0eab-4838-b834-e487e501f0df	firma	ordenes/ORD-000038/1756411629041-n3zwf.png	image/png	4068	2025-08-28 15:07:09.048676-05
a054c571-4180-47ff-b12b-ee21fa6c1515	a1579693-1222-41fe-a63d-515abee1ae47	foto	ordenes/ORD-000037/1756411677894-o3w4q.jpg	image/jpeg	9252	2025-08-28 15:07:57.90317-05
cd5b94c1-debb-446e-88ea-7996993d8935	a1579693-1222-41fe-a63d-515abee1ae47	firma	ordenes/ORD-000037/1756411677907-bu62e.png	image/png	4144	2025-08-28 15:07:57.91439-05
ecb4921b-387b-4799-a54b-9915f4c45384	1c273b36-f305-45cb-a187-045702b46e10	foto	ordenes/ORD-000036/1756411694838-026ks.jpg	image/jpeg	9252	2025-08-28 15:08:14.847561-05
64e38f0b-c34e-48dc-a6a5-788aa509e03d	1c273b36-f305-45cb-a187-045702b46e10	firma	ordenes/ORD-000036/1756411694850-jm36v.png	image/png	4953	2025-08-28 15:08:14.857934-05
b1559f01-ceaf-4090-ae7f-562887f1a837	18106add-d2ec-45b1-828e-c991e70470f2	foto	ordenes/ORD-000035/1756411701536-gj97w.jpg	image/jpeg	6098	2025-08-28 15:08:21.545528-05
b125670f-e6e8-4797-b76e-76f4cdc5d1b2	18106add-d2ec-45b1-828e-c991e70470f2	firma	ordenes/ORD-000035/1756411701547-jhx3p.png	image/png	2063	2025-08-28 15:08:21.554447-05
0696fd61-269f-402e-9c41-385392dc6b3a	b3f29769-c2e7-429e-a676-0cc6f1706fed	foto	ordenes/ORD-000034/1756411714794-16e5k.jpg	image/jpeg	44939	2025-08-28 15:08:34.804767-05
66c071e8-681e-4c52-b3a7-546071cf4f82	b3f29769-c2e7-429e-a676-0cc6f1706fed	firma	ordenes/ORD-000034/1756411714808-d43s2.png	image/png	5765	2025-08-28 15:08:34.815749-05
5db8ac8d-602b-4315-bb7c-80b0ea5cf6e9	6ef6375b-6ec6-4e87-b42e-bd179fd0d474	foto	ordenes/ORD-000033/1756411726616-z7g4l.jpg	image/jpeg	44939	2025-08-28 15:08:46.624526-05
a5c21f5d-ba02-4990-8610-8801a81b2254	6ef6375b-6ec6-4e87-b42e-bd179fd0d474	firma	ordenes/ORD-000033/1756411726627-x8xyn.png	image/png	5246	2025-08-28 15:08:46.634759-05
6222808d-a7f6-4eff-b3bc-e4e044fb47e9	c9734093-daee-482a-b49c-ddbe9f376346	foto	ordenes/ORD-000044/1756479450767-lf36p.jpg	image/jpeg	9252	2025-08-29 09:57:30.789335-05
e7736b65-8489-4198-b779-868d451f4d22	c9734093-daee-482a-b49c-ddbe9f376346	firma	ordenes/ORD-000044/1756479450793-kj9ct.png	image/png	5491	2025-08-29 09:57:30.800975-05
647ada07-26ca-4d0a-bdf1-6d57b08a8ac3	0f364933-be0d-4d18-80c8-3928e719829a	foto	ordenes/ORD-000043/1756479489929-pkevc.jpg	image/jpeg	71773	2025-08-29 09:58:09.941176-05
0aa29305-0dd8-410c-b78d-9d05c59058f6	0f364933-be0d-4d18-80c8-3928e719829a	firma	ordenes/ORD-000043/1756479489946-cou19.png	image/png	6147	2025-08-29 09:58:09.956746-05
83f829de-24a6-4f25-aeb5-d51944e7609b	1516e543-fb43-4807-9eb6-00b3f3b66cb7	foto	ordenes/ORD-000045/1756480826649-7x5bz.jpg	image/jpeg	9252	2025-08-29 10:20:26.659391-05
ee7c2ac9-c321-48bd-821c-e7654ca03f51	1516e543-fb43-4807-9eb6-00b3f3b66cb7	firma	ordenes/ORD-000045/1756480826663-9z854.png	image/png	4970	2025-08-29 10:20:26.66998-05
9b0610eb-f184-4b58-98e8-e2b07f49c1da	ae361293-c148-4538-8e89-5649430c9c99	foto	ordenes/ORD-000046/1756481374033-9dn0l.jpg	image/jpeg	6098	2025-08-29 10:29:34.0439-05
6b21e60a-51c0-4dc3-b218-2ea819964375	ae361293-c148-4538-8e89-5649430c9c99	firma	ordenes/ORD-000046/1756481374047-egxgc.png	image/png	5763	2025-08-29 10:29:34.056301-05
a01aafc5-15fc-481f-b6dd-1f6986febf3a	53eeca4f-ee81-4bb1-8bd8-2eb306decd17	foto	2025/08/29/ordenes/ORD-000047/1756503613918-batkpq.jpg	image/jpeg	\N	2025-08-29 16:40:13.929354-05
14701dab-a961-4676-a160-433a6419a918	53eeca4f-ee81-4bb1-8bd8-2eb306decd17	firma	2025/08/29/ordenes/ORD-000047/1756503613934-dh7w0d.png	image/png	\N	2025-08-29 16:40:13.941489-05
1f7301c7-a2d3-4682-b02e-9b88d70feb1c	706174d3-3a36-4113-ace1-11cf11ae1aae	foto	2025/08/29/ordenes/ORD-000048/1756503633800-qpj1fl.jpg	image/jpeg	\N	2025-08-29 16:40:33.815022-05
7efe45b3-72be-4dd9-ba60-e94b3a1db070	706174d3-3a36-4113-ace1-11cf11ae1aae	firma	2025/08/29/ordenes/ORD-000048/1756503633819-rokf52.png	image/png	\N	2025-08-29 16:40:33.827174-05
4c49d438-7c79-41f8-a416-16da57198e4d	ae478711-4d22-4d7b-bf78-c98ddeb9678a	foto	ordenes/ORD-000049/1756504777492-72f272b9.jpg	image/jpeg	9252	2025-08-29 16:59:37.501288-05
056d0eca-fb54-407f-a68a-5602c386b056	ae478711-4d22-4d7b-bf78-c98ddeb9678a	firma	ordenes/ORD-000049/1756504777506-28323859.png	image/png	4258	2025-08-29 16:59:37.513518-05
65c860f6-3f74-40e8-9e82-249925852c4a	4813fb02-e390-4e16-b0ad-17af3d4ae458	foto	ordenes/ORD-000050/1756504876811-ed9442ac.jpg	image/jpeg	9252	2025-08-29 17:01:16.820332-05
4c4b14e1-c661-41e3-9d73-37f2b2411c45	4813fb02-e390-4e16-b0ad-17af3d4ae458	firma	ordenes/ORD-000050/1756504876824-090e9170.png	image/png	4119	2025-08-29 17:01:16.831261-05
a6f9f81a-8b51-4992-9d91-622ec9ec787b	a4735703-c195-43b2-8e6d-02cde99e51f3	foto	ordenes/ORD-000051/1756504963499-220d7e22.jpg	image/jpeg	9252	2025-08-29 17:02:43.506965-05
83f60587-62f6-43b4-8bf9-39a9952f0944	a4735703-c195-43b2-8e6d-02cde99e51f3	foto	ordenes/ORD-000051/1756504963511-d528d500.jpg	image/jpeg	6098	2025-08-29 17:02:43.516574-05
b13abb12-a174-4351-ab30-d47c015726e5	a4735703-c195-43b2-8e6d-02cde99e51f3	foto	ordenes/ORD-000051/1756504963520-58c0dc66.jpg	image/jpeg	71773	2025-08-29 17:02:43.527444-05
0b5a3291-aee8-4766-a364-3c25b408bafc	a4735703-c195-43b2-8e6d-02cde99e51f3	firma	ordenes/ORD-000051/1756504963530-7ca019f2.png	image/png	6916	2025-08-29 17:02:43.535344-05
90382852-e57c-459f-a59d-73d38ab40221	7bd4f252-83b3-4922-8595-90f3ce1b5f50	foto	ordenes/ORD-000052/1756575353809-d2b85204.jpg	image/jpeg	9252	2025-08-30 12:35:53.820529-05
3f8cdc11-fa02-4fcb-83b4-618730edf8ef	7bd4f252-83b3-4922-8595-90f3ce1b5f50	firma	ordenes/ORD-000052/1756575353825-a8069593.png	image/png	6708	2025-08-30 12:35:53.83331-05
fe0c6dce-016a-4f4d-b496-dd15a97a8a6a	48fcf5b2-74e2-4c1f-b084-72f87e0d4d6b	foto	ordenes/ORD-000053/1756646967835-343c7814.jpg	image/jpeg	9252	2025-08-31 08:29:27.846609-05
76b1b541-883d-4ae9-a5e3-2830c70b2f42	48fcf5b2-74e2-4c1f-b084-72f87e0d4d6b	firma	ordenes/ORD-000053/1756646967851-38ae0553.png	image/png	4617	2025-08-31 08:29:27.861239-05
07ae3e99-6acb-4b2a-984e-fcfa85363693	186b113b-1c57-40ae-bad9-b543e767dc5d	foto	ordenes/ORD-000054/1756647272981-a4df5566.jpg	image/jpeg	9252	2025-08-31 08:34:32.989261-05
f16f2f0e-199b-4f4b-a35c-e342a6c42442	186b113b-1c57-40ae-bad9-b543e767dc5d	firma	ordenes/ORD-000054/1756647272995-93f8bff7.png	image/png	3743	2025-08-31 08:34:33.001698-05
2d4a9940-3ac2-4f61-b81a-31bbfb6ef12f	91c48adc-81b0-485c-a3d6-58d311245767	foto	ordenes/ORD-000055/1756648385984-8c147fc2.jpg	image/jpeg	9252	2025-08-31 08:53:05.992623-05
92c4244f-6d0b-4dc4-8a80-d0f9c0238fd0	91c48adc-81b0-485c-a3d6-58d311245767	firma	ordenes/ORD-000055/1756648385996-68f15f8a.png	image/png	5278	2025-08-31 08:53:06.002499-05
29706674-f53a-484b-b756-2e72eaa9844a	9de3d1f3-f19d-45b1-8afd-54226b541b9c	foto	ordenes/ORD-000056/1756650475583-3faefcc4.jpg	image/jpeg	9252	2025-08-31 09:27:55.59168-05
579e088b-9bea-44a8-9da7-0971b3f1f23f	9de3d1f3-f19d-45b1-8afd-54226b541b9c	firma	ordenes/ORD-000056/1756650475597-1d228220.png	image/png	7295	2025-08-31 09:27:55.605239-05
a0e2fc3f-6290-4e61-b685-b4f9a1d06031	75227fe9-644a-498e-b65d-842cbba42e32	foto	ordenes/ORD-000057/1756661535285-e0694780.jpg	image/jpeg	9252	2025-08-31 12:32:15.294358-05
a6b02ef8-13d2-4cdc-a7f5-8dd8e5616e64	75227fe9-644a-498e-b65d-842cbba42e32	firma	ordenes/ORD-000057/1756661535299-84fe71dc.png	image/png	4008	2025-08-31 12:32:15.305823-05
dabff74e-3f08-4ac8-ad97-979c1764d733	2d571474-3cac-40db-9688-b9ee606248c3	foto	ordenes/ORD-000058/1756661550479-3eeac793.jpg	image/jpeg	9252	2025-08-31 12:32:30.489421-05
5a78a422-1784-48e1-87cb-3194bd22b1f0	2d571474-3cac-40db-9688-b9ee606248c3	firma	ordenes/ORD-000058/1756661550493-dc50123f.png	image/png	4858	2025-08-31 12:32:30.49881-05
3c13e173-b8b3-4c6d-a760-355a607e5c3e	ce7d6fcb-1bc8-47c3-97f7-2b4e73039aae	foto	ordenes/ORD-000059/1756661565050-8453716e.jpg	image/jpeg	9252	2025-08-31 12:32:45.058234-05
56f6c1f2-302e-4c54-a641-58fad686e89b	ce7d6fcb-1bc8-47c3-97f7-2b4e73039aae	firma	ordenes/ORD-000059/1756661565061-cf6084df.png	image/png	5537	2025-08-31 12:32:45.067088-05
bfe7125e-7ab8-46b2-977d-798e3652fec6	703d0246-2c78-42ac-a57d-5ddbac766fa0	foto	ordenes/ORD-000060/1756661578715-f8e553a5.jpg	image/jpeg	9252	2025-08-31 12:32:58.722812-05
77ccc5e1-76c0-459e-9e3c-1d396f4b531a	703d0246-2c78-42ac-a57d-5ddbac766fa0	firma	ordenes/ORD-000060/1756661578726-23867748.png	image/png	7271	2025-08-31 12:32:58.731332-05
f030aa71-8823-4ac8-bc87-8cdcc2ab4c8e	7d141298-7b93-4f87-bbfb-fd0fa81381e0	foto	ordenes/ORD-000061/1756661590273-5d256fdb.jpg	image/jpeg	9252	2025-08-31 12:33:10.281319-05
27727df5-b31d-4e2f-b267-93644b72f0b6	7d141298-7b93-4f87-bbfb-fd0fa81381e0	firma	ordenes/ORD-000061/1756661590285-08b25801.png	image/png	8432	2025-08-31 12:33:10.290958-05
7a5df3c1-e5da-4477-ac10-ae2b8ae1cd01	a20dce83-d315-4668-a3e3-2bc8dec5d9d8	foto	ordenes/ORD-000062/1756661600911-189b9f31.jpg	image/jpeg	9252	2025-08-31 12:33:20.918276-05
ab65fddf-3d6e-454a-85e3-6d3ae5e92e42	a20dce83-d315-4668-a3e3-2bc8dec5d9d8	firma	ordenes/ORD-000062/1756661600921-c55d4309.png	image/png	7215	2025-08-31 12:33:20.927569-05
e9fdc291-0e4e-46bb-9182-40a7015e23fd	ac804eff-39c7-4bc1-8f84-cb456092c367	foto	ordenes/ORD-000063/1756661615298-45538ca0.jpg	image/jpeg	9252	2025-08-31 12:33:35.304578-05
ab6318b2-c322-4904-8e52-6a674c28f458	ac804eff-39c7-4bc1-8f84-cb456092c367	firma	ordenes/ORD-000063/1756661615307-cce15c7b.png	image/png	5951	2025-08-31 12:33:35.313221-05
f90011a1-5d7c-4ed2-8111-7e221bde3dfa	e8a0ec72-e10d-493a-bedd-efff336512ba	foto	ordenes/ORD-000064/1756661626160-93f20249.jpg	image/jpeg	9252	2025-08-31 12:33:46.167498-05
96e5a42c-0333-4502-9ce7-4440fbc5d86c	e8a0ec72-e10d-493a-bedd-efff336512ba	firma	ordenes/ORD-000064/1756661626171-129d1971.png	image/png	9340	2025-08-31 12:33:46.176556-05
a016f411-c2d1-4187-86c2-4355a1f73b2f	385bf766-c077-45b9-80ab-0f42d471bb6f	foto	ordenes/ORD-000065/1756661638863-b44076af.jpg	image/jpeg	9252	2025-08-31 12:33:58.869972-05
0b6d213c-7e2d-4b3b-ae61-87ff98aeb82a	385bf766-c077-45b9-80ab-0f42d471bb6f	firma	ordenes/ORD-000065/1756661638873-12686699.png	image/png	12277	2025-08-31 12:33:58.879481-05
1d3cc173-75ca-42e6-a1ad-0d3688e5cf8a	b22d3abb-fff8-4db6-bf28-739e5e8818cc	foto	ordenes/ORD-000066/1756661671012-11fe2406.jpg	image/jpeg	9252	2025-08-31 12:34:31.018975-05
60f71798-bd37-4edd-85d2-ad37f1bcc0c8	b22d3abb-fff8-4db6-bf28-739e5e8818cc	firma	ordenes/ORD-000066/1756661671022-fb62dab1.png	image/png	7285	2025-08-31 12:34:31.027543-05
cfa627ac-25c2-4971-b396-5398d1c9f500	873872d8-1b00-4a31-8a99-93f91418e6c1	foto	ordenes/ORD-000067/1756674046285-84c68649.jpg	image/jpeg	9252	2025-08-31 16:00:46.294397-05
7e27c137-9d70-4f0d-9356-f2148011fa70	873872d8-1b00-4a31-8a99-93f91418e6c1	firma	ordenes/ORD-000067/1756674046300-537c8767.png	image/png	4896	2025-08-31 16:00:46.305809-05
\.


--
-- Data for Name: factura_detalle; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.factura_detalle (id, factura_id, concepto, cantidad, precio_unit, total_linea, plan_id, servicio_id) FROM stdin;
\.


--
-- Data for Name: facturas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.facturas (id, usuario_id, numero_fiscal, periodo, fecha_emision, fecha_vencimiento, subtotal, impuestos, descuentos, total, estado, pdf_url, created_at) FROM stdin;
\.


--
-- Data for Name: inventario_equipos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_equipos (id, tipo, modelo, serie, mac, estado, ubicacion, tecnico_id, usuario_id, precinto, created_at) FROM stdin;
\.


--
-- Data for Name: inventario_materiales; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.inventario_materiales (id, descripcion, unidad, stock_actual, stock_minimo, activo) FROM stdin;
\.


--
-- Data for Name: mov_inventario; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.mov_inventario (id, tipo, equipo_id, material_id, qty, origen, destino, orden_id, notas, created_at) FROM stdin;
\.


--
-- Data for Name: municipios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.municipios (id, codigo, nombre, activo) FROM stdin;
005123ac-5dce-4c11-9665-01e2d73b3df2	BARRANQUILLA	BARRANQUILLA	t
6988210d-c9b9-4d73-bb87-09017564e336	SOLEDAD	SOLEDAD	t
141d6066-e03d-47aa-8a42-71511e23dd67	MALAMBO	MALAMBO	t
\.


--
-- Data for Name: notas_credito; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notas_credito (id, factura_id, motivo, monto, fecha, admin_id, audit_json) FROM stdin;
\.


--
-- Data for Name: ordenes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ordenes (id, codigo, venta_id, usuario_id, tipo, estado, created_at, lat, lng, onu_serial, vlan, precinto, cerrada_por, cerrada_at) FROM stdin;
1d88b098-a4fe-4989-b95d-d5926ad8a3c0	ORD-000001	c6a0f70c-e19b-4b37-9888-af4717d3c18c	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-13 20:20:44.876257-05	\N	\N	\N	\N	\N	\N	\N
7dd2f076-c48a-40b6-84db-52c470fb86b6	ORD-000002	497c33e0-aee0-461d-a988-9aa7d731e8ac	f4677737-9930-4da1-8e3d-194151a49116	instalacion	cerrada	2025-08-13 20:27:06.94345-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 20:46:52.274-05
d0e42b8b-be7c-4096-9eae-75f7a957bcaf	ORD-000003	418fb892-7e4d-4a48-a176-a6636e960ae7	f73f34e8-02d8-4aa4-912b-524561ac7801	instalacion	cerrada	2025-08-13 20:57:00.02628-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 20:57:53.162-05
22754547-9ea1-4f94-8053-634ef4e2e62e	ORD-000004	de0a2221-e09b-4258-8afe-877a2e07652f	af9a5f66-b5d5-4a10-aa5c-71dee7793ef6	instalacion	cerrada	2025-08-13 21:04:58.971925-05	4.711	-74.072	TEST	110	\N	TEC-001	2025-08-13 21:06:11.127-05
53f731e9-55de-4674-8e60-65e55ada0c33	ORD-000005	fbb47ea4-f316-43e8-8b14-5c42d7fb43c8	d2d81a5d-728b-4d13-9c22-177b3e7989b8	instalacion	cerrada	2025-08-13 21:07:34.820323-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 21:16:42.875-05
89693c47-979d-464d-aa89-901c120241a0	ORD-000006	91eac6ea-ed4f-4938-bebc-b9b4433db800	e9cd2fb6-45ae-4117-a7cc-d606593740d8	instalacion	cerrada	2025-08-13 21:30:01.897283-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 21:31:11.018-05
0f7f70fb-d34f-4ca1-96cd-6d737e3ee82b	ORD-000007	1a5a2b3a-5e62-43e0-80ce-aeaca5a0e5f7	827d0471-2d76-4bbe-a364-93081992a32e	instalacion	cerrada	2025-08-13 21:40:35.790618-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 21:41:12.551-05
db939f11-afa3-41f2-a932-ee9ab09c4dc0	ORD-000008	06582703-d5d9-4d04-9b1c-8fcd6ca0ad79	f73f34e8-02d8-4aa4-912b-524561ac7801	instalacion	cerrada	2025-08-13 21:47:48.043356-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 21:51:04.609-05
de9a712c-ad6b-490a-938b-7269cb38c56d	ORD-000009	e842d716-251a-42ff-bf98-ad4a07ae7b46	588f3ddc-cc2d-4b58-a9e4-3c84bc032827	instalacion	cerrada	2025-08-13 22:02:30.431709-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 22:13:33.315-05
e4161186-e93c-481e-b39c-4cfc166ccd3d	ORD-000010	5ebcb3ea-85c1-4f10-9a59-bba44dec8c75	d76407e1-e4ef-4a22-b216-336c792ce61a	instalacion	cerrada	2025-08-13 22:04:06.759544-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-13 22:16:38.055-05
2330179f-a5e4-425c-931d-f49f0b327451	ORD-000011	8f704aca-55e2-4f50-8dc4-3a1640299bac	96bf6d92-061b-409e-bc4a-86d30edc1a10	instalacion	cerrada	2025-08-14 10:39:43.766938-05	\N	\N	\N	\N	\N	tecnico-demo	2025-08-14 14:00:29.62-05
2ee14414-c2a8-42e0-a16c-24df7706f999	ORD-000012	0238fb34-3d87-4333-8ee7-8559e26585bc	0ee9864a-d7f7-46a6-b53c-9f4d0c1a229a	instalacion	cerrada	2025-08-14 14:03:53.685237-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-14 14:08:24.852-05
0dfc2bf7-e9c1-4c70-ab7d-7735d54e519a	ORD-000025	1a885937-a630-4d9e-893f-ffafcf715c74	f77e2e5f-9088-44b7-b8e2-4ea730492f0d	instalacion	cerrada	2025-08-21 15:09:48.526134-05	4.65	-74.08	HWTC1755807002	200	P-1755807002	tec1	2025-08-21 15:10:02.987-05
782b97cd-b650-4254-8e6a-544cb2a5479e	ORD-000013	b2cf6533-ead2-45d9-bf11-c4d08681ec73	e5b878ab-50d9-416f-be07-b5cb27534193	instalacion	cerrada	2025-08-14 15:37:02.640361-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-14 15:50:23.029-05
3fcb7ab0-2fe0-4497-98cf-813fe57872b5	ORD-000014	42fd4c8b-bfb6-407f-ba94-bd9eba553d73	04e35388-a50d-4d55-a5fc-3521b54b6e68	instalacion	cerrada	2025-08-14 15:51:16.26298-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-14 15:51:40.841-05
d8de0b1a-9b1b-49ad-bff6-0ac1c2a02cf5	ORD-000015	9a3f1290-6d43-418d-9e2c-b8a4fe33d041	74986c44-4c01-45b5-90b3-e4cfb2dfb5eb	instalacion	cerrada	2025-08-14 15:59:08.067518-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-14 15:59:32.836-05
181df4e0-3d4c-47e6-81fb-a74963e4afc4	ORD-000016	e3050916-970b-4eb6-93e7-2e65f3fcc401	0ee9864a-d7f7-46a6-b53c-9f4d0c1a229a	instalacion	cerrada	2025-08-19 11:35:17.94849-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-19 11:35:53.508-05
0a17e5ef-f4d3-44ff-a60b-e04cc0aed4f5	ORD-000017	a79042da-69f2-48af-8a55-3a33686baf56	5ee1a37f-ab38-4513-bbb1-690b51caf81f	instalacion	cerrada	2025-08-19 11:58:24.79765-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-19 11:58:24.871-05
1959794e-70f1-42df-b7bf-e4cd014d47ac	ORD-000018	f02fe6de-fcd1-4570-ac7c-5be9e437a62d	5ee1a37f-ab38-4513-bbb1-690b51caf81f	instalacion	cerrada	2025-08-19 11:58:54.496231-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-19 11:58:54.564-05
352854c3-27b6-459e-be3b-210556dff3ef	ORD-000019	2c192569-fcc1-4021-99d7-d4c11ce0fcbd	5ee1a37f-ab38-4513-bbb1-690b51caf81f	instalacion	cerrada	2025-08-20 11:15:12.867517-05	4.711	-74.072	ZTEG12345678	110	P-0001	TEC-001	2025-08-20 11:15:13.064-05
11da001e-7aa5-48de-b84d-43b7876a4a50	ORD-000021	e08bfe79-fbd0-4e4d-bc1a-432dd4ce07d3	7ce89f8c-cc2e-4fd0-9695-8a1184c39b0d	instalacion	cerrada	2025-08-21 09:25:10.717303-05	4.65	-74.08	HWTC12345678	200	P-001	tec1	2025-08-21 09:38:52.086-05
1ee9b0a2-3b67-4d2e-ba8c-72fed4d73309	ORD-000020	a147f816-1794-4b28-9ed4-5d02a4d9945e	7a9585d7-fe29-4c6d-b3a6-9c80a935124c	instalacion	cerrada	2025-08-20 16:22:59.409986-05	4.65	-74.08	HWTC12345678	200	P-001	tec1	2025-08-21 09:39:45.434-05
12c75d88-c1fe-4895-beae-faed56e493e7	ORD-000022	fdff628b-6bf5-4676-8b5f-16f1e6e0f58f	9cc349fe-fa7f-47bd-84a2-4018344ac5ec	instalacion	cerrada	2025-08-21 09:49:18.377085-05	4.65	-74.08	HWTC1755787758	200	P-1755787758	tec1	2025-08-21 09:49:18.523-05
29e1af19-9966-4ca7-a560-725dbf7b1b98	ORD-000023	68d63b55-8088-4cf6-a4a8-28c67d3f3971	1fff99c3-1c0d-446e-9c6c-a47e2b63a0fc	instalacion	cerrada	2025-08-21 10:36:26.82714-05	4.65	-74.08	HWTC1755787758	200	P-1755787758	tec1	2025-08-21 10:36:26.924-05
9859bb40-a126-45c4-8cfc-c2a67338f1c1	ORD-000024	aec97267-509a-4758-823c-5d76eb3c09f5	78d51b62-a048-4ad1-a756-44a9cbae7911	instalacion	cerrada	2025-08-21 15:06:01.271614-05	4.711	-74.072	ZTEG12345600	110	P-0002	tecnico-demo	2025-08-27 14:57:35.116-05
54a5ef8a-e623-4e69-b359-c0e912c39a5a	ORD-000026	f401c37b-04f3-41c0-aa14-aae646ab122c	d070c040-bff0-4913-a3b4-6283d06ef698	instalacion	cerrada	2025-08-27 11:27:50.54762-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-27 14:58:22.106-05
13510fea-b372-489e-8d64-be495fb525cf	ORD-000027	ab1c5556-8839-4871-a7f7-da956f442489	2062a0fd-4ae2-4a18-a52a-dc8dd5bc151a	instalacion	cerrada	2025-08-27 14:59:20.220549-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-27 14:59:46.743-05
68a72c38-b7c2-4608-8df6-4ce14802f7f7	ORD-000028	dcd81030-fd9a-4739-9b8e-0c20aca4351d	3810a8b7-cd11-400a-bec3-f647205e5c2f	instalacion	cerrada	2025-08-27 15:01:44.544968-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-27 15:02:13.963-05
6922f2fe-fff6-47f8-a30d-cbf95ba8f83f	ORD-000029	77e62395-e1b8-42e0-92f4-c202ebc42ff8	62e1681e-b52b-4f6d-a027-012aefa8dd45	instalacion	cerrada	2025-08-27 16:49:22.555853-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-27 16:49:41.06-05
3ff8ca7d-0397-443a-99a8-6b0a6b233e6d	ORD-000030	67b42cb3-01e7-49b5-851e-87ed37ab4ee8	8a2c3be1-f3ae-4b51-a59f-2218915cc7b7	instalacion	cerrada	2025-08-27 17:05:45.161388-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-27 17:06:10.604-05
1bf6e3c7-ddee-4920-a8e5-736ced3c0e42	ORD-000031	2a733814-8ac7-4c04-8bb7-35c2a328e955	8683c95c-5eb5-44a2-88b5-57a68784f111	instalacion	cerrada	2025-08-28 10:30:35.583959-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 10:31:04.501-05
77675493-e941-4983-9b11-b8a063c5f042	ORD-000032	a2e7a5b6-103c-4ae3-bdfc-18b23d1b331f	f607ce6f-8182-4607-b7ac-09208c42c6f6	instalacion	cerrada	2025-08-28 10:32:27.576171-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 10:33:12.672-05
376d4d5b-07ea-40d6-8e30-14c57ec9bf87	ORD-000042	0b748ec5-b818-4e9b-94ed-b60b1ee4de21	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-28 15:05:13.479177-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:05:45.058-05
780c046d-58cc-4d15-9ad9-05ec63d282c4	ORD-000041	c6fbdd1d-9f13-4395-9421-9d857f1bfd89	87869bfa-5525-489b-96e0-365ebf3a0c63	instalacion	cerrada	2025-08-28 15:05:11.702039-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:05:58.611-05
cb8febbe-6ab8-43da-8a35-59e0d6708cdd	ORD-000040	74d1746e-ff84-49e4-a960-e5d28d54e7e6	f4677737-9930-4da1-8e3d-194151a49116	instalacion	cerrada	2025-08-28 15:05:09.713084-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:06:20.271-05
a40fff73-0cb2-427a-bb9a-b4946d2e65f7	ORD-000039	9053e99c-7fa9-4e8f-8dc7-67edf9c73350	f73f34e8-02d8-4aa4-912b-524561ac7801	instalacion	cerrada	2025-08-28 15:05:07.597906-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:06:36.551-05
07f1001c-0eab-4838-b834-e487e501f0df	ORD-000038	05566472-e8ca-4015-bd2e-658990a7cad7	946c277c-e557-4cbb-80ee-459c95aad637	instalacion	cerrada	2025-08-28 15:05:05.272692-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:07:09.023-05
a1579693-1222-41fe-a63d-515abee1ae47	ORD-000037	f1f3dcdc-d884-4674-a74e-bd1fa33f02c8	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-28 15:05:03.288374-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:07:57.889-05
1c273b36-f305-45cb-a187-045702b46e10	ORD-000036	3c257c76-674e-49ba-af33-51e343a9718e	7b70930b-4104-4ba0-a7b4-757932af4f0e	instalacion	cerrada	2025-08-28 15:05:01.225446-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:08:14.834-05
18106add-d2ec-45b1-828e-c991e70470f2	ORD-000035	3dac3154-8c54-4f55-85b6-c827cc8fbd1c	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-28 15:04:57.528525-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:08:21.532-05
b3f29769-c2e7-429e-a676-0cc6f1706fed	ORD-000034	4028845f-9093-4e17-92ad-3077f806e598	809a6932-fbe0-46bb-80bd-2936dbfe235e	instalacion	cerrada	2025-08-28 15:04:52.299887-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:08:34.788-05
6ef6375b-6ec6-4e87-b42e-bd179fd0d474	ORD-000033	76ddc7f0-0438-4ceb-8405-1aceb9d28d9c	809a6932-fbe0-46bb-80bd-2936dbfe235e	instalacion	cerrada	2025-08-28 15:04:48.286921-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-28 15:08:46.611-05
c9734093-daee-482a-b49c-ddbe9f376346	ORD-000044	5d230654-dc84-4d3c-8c57-6fa7c0a66617	4bb257d7-24e2-4fc7-bc2f-741e9a634243	instalacion	cerrada	2025-08-29 09:25:49.282476-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 09:57:30.759-05
0f364933-be0d-4d18-80c8-3928e719829a	ORD-000043	af609173-efb9-49e4-9307-5f74b4a2091b	c9b072ba-1cc1-4f7e-bd97-9a1be55582e4	instalacion	cerrada	2025-08-29 09:13:33.35377-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 09:58:09.922-05
1516e543-fb43-4807-9eb6-00b3f3b66cb7	ORD-000045	2856fc50-fa19-4b59-bf0b-b82c122f9ae1	58465a3e-b016-4418-ab83-95983406b638	instalacion	cerrada	2025-08-29 10:19:58.477951-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 10:20:26.643-05
ae361293-c148-4538-8e89-5649430c9c99	ORD-000046	0c13ebb8-1b64-4243-94a5-871c6e8cc35f	1d456856-c9a4-4917-bd43-f574661c05f5	instalacion	cerrada	2025-08-29 10:29:00.465546-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 10:29:34.026-05
53eeca4f-ee81-4bb1-8bd8-2eb306decd17	ORD-000047	daeeaae6-b1c8-4e2d-bd4f-f6768031d6b4	1d456856-c9a4-4917-bd43-f574661c05f5	instalacion	cerrada	2025-08-29 16:39:02.897313-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 16:40:13.911-05
706174d3-3a36-4113-ace1-11cf11ae1aae	ORD-000048	50ce0a58-233c-425f-ab36-704054ef3393	9a9a03e2-a2d5-4901-ac75-5f7cdbd0ce1d	instalacion	cerrada	2025-08-29 16:39:38.583952-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 16:40:33.793-05
ae478711-4d22-4d7b-bf78-c98ddeb9678a	ORD-000049	b998502a-5b21-4889-b830-21eec2559b34	809a6932-fbe0-46bb-80bd-2936dbfe235e	instalacion	cerrada	2025-08-29 16:58:40.827178-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 16:59:37.485-05
4813fb02-e390-4e16-b0ad-17af3d4ae458	ORD-000050	4608919d-8126-43d1-8e90-9b452a7ea9cb	809a6932-fbe0-46bb-80bd-2936dbfe235e	instalacion	cerrada	2025-08-29 17:00:29.443926-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 17:01:16.804-05
a4735703-c195-43b2-8e6d-02cde99e51f3	ORD-000051	5f5e6061-b2a0-4791-a7ed-af1bfe3043f3	5c4e775c-a201-462b-8e1c-c049686ee698	instalacion	cerrada	2025-08-29 17:02:00.546735-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-29 17:02:43.493-05
7bd4f252-83b3-4922-8595-90f3ce1b5f50	ORD-000052	c7e1433a-a34f-43f8-9f62-70f817f631c7	8e1597e7-33c9-40c1-9100-141933812459	instalacion	cerrada	2025-08-30 12:35:05.867075-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-30 12:35:53.801-05
48fcf5b2-74e2-4c1f-b084-72f87e0d4d6b	ORD-000053	f5e7a627-45b7-4673-b468-1ca5e2d18eb6	2ccf6866-66d6-4770-bc03-f468253646eb	instalacion	cerrada	2025-08-31 08:27:55.484692-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 08:29:27.827-05
186b113b-1c57-40ae-bad9-b543e767dc5d	ORD-000054	58608052-2db1-49c7-92d8-de63f82c9513	092c7229-0f4b-4a8d-b15f-a6af1116b8dd	instalacion	cerrada	2025-08-31 08:33:50.718875-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 08:34:32.975-05
91c48adc-81b0-485c-a3d6-58d311245767	ORD-000055	060e9793-7a83-4143-ae42-863ab77b03ac	b77e211b-fee3-42b5-914f-987d0268ca9c	instalacion	cerrada	2025-08-31 08:52:27.481869-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 08:53:05.979-05
9de3d1f3-f19d-45b1-8afd-54226b541b9c	ORD-000056	27bfe543-e877-4bb2-b140-bbf069ba3f17	30b18dd1-49cd-481a-9ab5-c13680c79ba1	instalacion	cerrada	2025-08-31 09:22:55.730453-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 09:27:55.575-05
75227fe9-644a-498e-b65d-842cbba42e32	ORD-000057	2421492b-9d93-4e5b-89c7-7e5226104341	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-31 09:58:48.432761-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:32:15.278-05
2d571474-3cac-40db-9688-b9ee606248c3	ORD-000058	d42725c7-ef52-4a9c-b264-262c2407f0a5	68598d9c-a7bd-4a4a-be2e-f0391cdefb2d	instalacion	cerrada	2025-08-31 10:04:14.86739-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:32:30.473-05
ce7d6fcb-1bc8-47c3-97f7-2b4e73039aae	ORD-000059	877b5ced-35fc-4b1a-b352-45ab1706d051	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-31 11:09:49.535468-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:32:45.038-05
703d0246-2c78-42ac-a57d-5ddbac766fa0	ORD-000060	86876131-ce2e-426a-a047-1a11fc871e63	9753dadb-a51a-4e93-ac31-94a5ffe0365d	instalacion	cerrada	2025-08-31 11:15:07.069894-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:32:58.71-05
7d141298-7b93-4f87-bbfb-fd0fa81381e0	ORD-000061	5faff5f2-2094-4d86-a2cd-9182ef21d72f	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-31 11:54:19.540364-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:33:10.267-05
a20dce83-d315-4668-a3e3-2bc8dec5d9d8	ORD-000062	bb1fdfbb-2524-4f6c-9fed-3c90b22524a9	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-31 11:58:35.551398-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:33:20.905-05
ac804eff-39c7-4bc1-8f84-cb456092c367	ORD-000063	aed4f84b-7b9e-4ad0-a951-cde69a4a55de	e7dd5e37-8dff-4ba8-a1ad-7754cea78f95	instalacion	cerrada	2025-08-31 11:59:05.499643-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:33:35.293-05
e8a0ec72-e10d-493a-bedd-efff336512ba	ORD-000064	cb741f0d-afe8-4fb7-8eeb-5845f3455609	04363624-3b11-415f-b133-370e6375b322	instalacion	cerrada	2025-08-31 12:17:15.193063-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:33:46.155-05
385bf766-c077-45b9-80ab-0f42d471bb6f	ORD-000065	a8f64020-6bc9-4a98-8038-466fe0dedb02	e7dd5e37-8dff-4ba8-a1ad-7754cea78f95	instalacion	cerrada	2025-08-31 12:19:23.295591-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:33:58.858-05
b22d3abb-fff8-4db6-bf28-739e5e8818cc	ORD-000066	bcf420e9-5de4-4f6a-9730-904c0047f3bb	98480b51-b943-4cc4-8aad-97df7d36c9ef	instalacion	cerrada	2025-08-31 12:29:34.346454-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 12:34:31.007-05
873872d8-1b00-4a31-8a99-93f91418e6c1	ORD-000067	40de531f-074d-41a0-b3fb-ca1d4b316a27	bad773a4-fb71-4b8f-a61c-dccf31fe5e5e	instalacion	cerrada	2025-08-31 15:59:54.716913-05	4.711	-74.072	ZTEG12345678	110	P-0001	tecnico-demo	2025-08-31 16:00:46.275-05
0f1f7301-af65-4d3f-80c6-d9dde3446a31	ORD-000068	85dfc3e5-ee65-4fc5-9333-5dbe790e6cd5	04363624-3b11-415f-b133-370e6375b322	instalacion	pendiente	2025-08-31 16:09:31.008038-05	\N	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: ordenes_servicio; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ordenes_servicio (id, tipo, ticket_id, usuario_id, tecnico_id, estado, cita_inicio, cita_fin, geolat, geolng, firma_url, cierre_notas, created_at) FROM stdin;
\.


--
-- Data for Name: pagos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pagos (id, factura_id, usuario_id, medio, referencia, monto, fecha, conciliado) FROM stdin;
\.


--
-- Data for Name: paises; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.paises (id, nombre) FROM stdin;
89e323c1-3b1e-4148-a52a-a04c9d4f9173	Colombia
\.


--
-- Data for Name: permisos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.permisos (id, recurso, accion) FROM stdin;
dcb7b11f-0bdd-4dfb-95f7-5ed99bbfec68	ordenes	leer
5ebbad1f-b59b-4033-9470-77cf16d3d49c	ordenes	cerrar
b574adf8-5171-447f-a899-abd9fa7db76f	ventas	crear
\.


--
-- Data for Name: planes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.planes (id, nombre, tipo, velocidad_mbps, activo, codigo, vel_mbps, alta_costo, mensual) FROM stdin;
de59d416-9501-40ea-8710-439acbf3636b	Hogar 100	internet	100	t	INT-003	0	0.00	0.00
d8f10b66-96c2-4a0d-bdfe-5554386e6bf2	Hogar 300	internet	300	t	INT-002	0	0.00	0.00
983cb1ab-20a5-41af-ad99-cf3562a788d9	TV Básica	tv	0	t	INT-001	0	0.00	0.00
aa0dd1c7-5893-49ce-a38d-c3890b9259c6	Internet 200M	internet	0	t	INT-200	200	80000.00	50000.00
18dc2bd9-aca2-49d8-8c29-55853ba2e993	Internet 300M	internet	0	t	INT-300	300	80000.00	60000.00
4848005c-a0f2-4a13-9c6f-20d7ab477421	Internet 500M	internet	0	t	INT-500	500	80000.00	90000.00
\.


--
-- Data for Name: rol_permisos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rol_permisos (rol_id, permiso_id) FROM stdin;
f5462711-1b4d-41e2-8590-f09980cba896	dcb7b11f-0bdd-4dfb-95f7-5ed99bbfec68
f5462711-1b4d-41e2-8590-f09980cba896	5ebbad1f-b59b-4033-9470-77cf16d3d49c
f5462711-1b4d-41e2-8590-f09980cba896	b574adf8-5171-447f-a899-abd9fa7db76f
f5e02324-1e24-4c8b-9595-426d3972d39b	dcb7b11f-0bdd-4dfb-95f7-5ed99bbfec68
f5e02324-1e24-4c8b-9595-426d3972d39b	5ebbad1f-b59b-4033-9470-77cf16d3d49c
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.roles (id, nombre) FROM stdin;
f5462711-1b4d-41e2-8590-f09980cba896	admin
f5e02324-1e24-4c8b-9595-426d3972d39b	tecnico
f952083c-b542-4da1-b998-73ad06d9d29e	agente
\.


--
-- Data for Name: sectores; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sectores (id, municipio_codigo, zona, nombre, activo) FROM stdin;
5687b922-74e3-4edb-a345-754d0edbefa1	BARRANQUILLA	BARRIO	LA CHINITA	t
914b19fc-5e36-417b-a471-473700360ab3	BARRANQUILLA	BARRIO	LA LUZ	t
61fa207f-4eed-49e2-b703-544d46c38783	BARRANQUILLA	BARRIO	VILLA SAN PABLO	t
c0748cc1-7017-4199-965c-632185f2b005	BARRANQUILLA	BARRIO	MODESTO	t
64790693-f177-4808-8087-717064ccb73e	BARRANQUILLA	BARRIO	TRUPILLOS	t
3ccd5beb-3c04-490a-83fd-ce0e4fc46da4	SOLEDAD	BARRIO	VILLA SOL	t
e0275f39-f072-4564-8aa5-33e322dbc2e0	SOLEDAD	BARRIO	MANANTIAL	t
222016a8-9507-42ae-b4f7-ba38e3b13c60	SOLEDAD	BARRIO	DON BOSCO	t
f81a61b4-e520-420a-a0b2-97ad7c4c212c	SOLEDAD	BARRIO	PARAISO	t
83fe94e2-5b08-4fd5-ba30-c1eea8aa2232	SOLEDAD	BARRIO	SEVILALREAL	t
41d768c5-c31d-476e-8c81-293f51a482f0	MALAMBO	BARRIO	CONCORDE	t
b43a572a-623c-45c6-8813-883dd0507acc	MALAMBO	BARRIO	VILLA CONCORDE	t
52411bd8-098a-4815-8783-276d4712d8e9	MALAMBO	BARRIO	EL CARMEN	t
35bfacf4-7ba0-40c0-b383-534e591d0df3	MALAMBO	BARRIO	BELLAVISTA	t
430059fc-1d0e-43e6-bf22-2954e6f056a6	BARRANQUILLA	CONJUNTO	MAYORQUI	t
81b56b3c-0dbb-4a85-af59-8e7b2c1045f9	BARRANQUILLA	CONJUNTO	BONAVENTO	t
bc062e48-b926-4870-873e-df5aad2d74fc	SOLEDAD	CONJUNTO	CEIBA	t
b19cc8d1-4bd1-4476-89a1-488d62d865b4	SOLEDAD	CONJUNTO	YARUMO	t
2d54e851-6801-4bb2-baf5-f7ab88488c2e	SOLEDAD	CONJUNTO	BARI	t
43ba7f9c-ecc7-4726-bcc8-e704142b07d6	MALAMBO	CONJUNTO	VILLA MALAMBO	t
\.


--
-- Data for Name: smartolt_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.smartolt_logs (id, endpoint, metodo, request_id, "timestamp", payload_redacted, status_code, response_trunc, error_text, retry_count, correlacion) FROM stdin;
\.


--
-- Data for Name: tarifas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tarifas (id, plan_id, moneda, precio, impuesto_pct) FROM stdin;
5eca504f-52ba-4b50-8fe6-7377a022643f	de59d416-9501-40ea-8710-439acbf3636b	COP	60000.00	19.00
2581faa5-53dd-4163-be5a-f1dcb2dd0c1e	d8f10b66-96c2-4a0d-bdfe-5554386e6bf2	COP	90000.00	19.00
cb4dea2b-58ac-466a-b708-89b0bcb41c5b	983cb1ab-20a5-41af-ad99-cf3562a788d9	COP	30000.00	19.00
\.


--
-- Data for Name: tecnicos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tecnicos (id, nombre, zona, activo) FROM stdin;
951e15c3-b593-48f4-bb93-e1459800fe5a	Carlos Pérez	Zona Norte	t
569f6776-ca09-4ea9-a0e0-6915239da870	Luisa Díaz	Zona Centro	t
\.


--
-- Data for Name: tickets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tickets (id, categoria, prioridad, sla_horas, estado, usuario_id, operador_id, agendado_para, created_at) FROM stdin;
\.


--
-- Data for Name: usuario_roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuario_roles (usuario_id, rol_id) FROM stdin;
dc733092-662a-41e6-abea-304fab09b121	f5462711-1b4d-41e2-8590-f09980cba896
bf01e076-b05f-415a-ac88-fe2a264b2c6a	f5e02324-1e24-4c8b-9595-426d3972d39b
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuarios (id, codigo, tipo_cliente, nombre, apellido, documento, email, telefono, estado, direccion, barrio_id, ciudad_id, geolat, geolng, created_at, updated_at, municipio_id, zona, barrio_conjunto, via, nombre_via, indicador, orientacion, numero_casa, saldo) FROM stdin;
98480b51-b943-4cc4-8aad-97df7d36c9ef	CLI-000179	hogar	carlos	perez	11111111	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 12:29:29.069455-05	2025-08-31 12:29:29.069455-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
022afa25-1b5b-4f41-93cb-570249dc0117	CLI-000125	corporativo	Tecno	SAS	900123456	contacto@tecno.com	6015550000	instalado	\N	\N	\N	\N	\N	2025-08-13 19:36:54.169101-05	2025-08-13 19:36:54.169101-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
bad773a4-fb71-4b8f-a61c-dccf31fe5e5e	CLI-000180	hogar	lamine	yamale	77777777	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 15:59:50.803391-05	2025-08-31 15:59:50.803391-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
af9a5f66-b5d5-4a10-aa5c-71dee7793ef6	CLI-000130	hogar	nervin	suarez	CC123457	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 21:02:25.215444-05	2025-08-13 21:02:25.215444-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
d2d81a5d-728b-4d13-9c22-177b3e7989b8	CLI-000131	hogar	kevin	carrillo	CC123458	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 21:07:20.332248-05	2025-08-13 21:07:20.332248-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
e9cd2fb6-45ae-4117-a7cc-d606593740d8	CLI-000132	hogar	ramon	valdes	CC123410	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 21:29:42.90786-05	2025-08-13 21:29:42.90786-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
827d0471-2d76-4bbe-a364-93081992a32e	CLI-000133	hogar	Pedro	Rolon	CC123411	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 21:40:23.817478-05	2025-08-13 21:40:23.817478-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
588f3ddc-cc2d-4b58-a9e4-3c84bc032827	CLI-000136	hogar	roberto	Rojas	CC123413	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 22:02:16.454448-05	2025-08-13 22:02:16.454448-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
d76407e1-e4ef-4a22-b216-336c792ce61a	CLI-000137	hogar	pedro	Rojas	CC123415	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-13 22:03:51.405738-05	2025-08-13 22:03:51.405738-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
96bf6d92-061b-409e-bc4a-86d30edc1a10	CLI-000138	hogar	Demo	Tecnico	CC000	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-14 10:39:43.674101-05	2025-08-14 10:39:43.674101-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
0ee9864a-d7f7-46a6-b53c-9f4d0c1a229a	CLI-000139	hogar	Demo	Tecnico	CC999	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-14 14:03:53.610413-05	2025-08-14 14:03:53.610413-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
e5b878ab-50d9-416f-be07-b5cb27534193	CLI-000140	hogar	jorge	mandon	CC-456732	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-14 15:37:02.535903-05	2025-08-14 15:37:02.535903-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
04e35388-a50d-4d55-a5fc-3521b54b6e68	CLI-000141	hogar	pedro	alvarez	CC9945	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-14 15:51:16.17967-05	2025-08-14 15:51:16.17967-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
74986c44-4c01-45b5-90b3-e4cfb2dfb5eb	CLI-000142	hogar	ramon	caldera	CC3459	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-14 15:59:07.969323-05	2025-08-14 15:59:07.969323-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
5ee1a37f-ab38-4513-bbb1-690b51caf81f	CLI-000144	hogar	Test	Tecnico	CC-DEMO	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-19 11:58:24.752696-05	2025-08-19 11:58:24.752696-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
7a9585d7-fe29-4c6d-b3a6-9c80a935124c	CLI-000147	hogar	pedro	gonzalez	CC7894	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-20 16:22:59.309861-05	2025-08-20 16:22:59.309861-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
7ce89f8c-cc2e-4fd0-9695-8a1184c39b0d	CLI-000148	hogar	karina	hernandez	CC7854	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 09:25:10.626056-05	2025-08-21 09:25:10.626056-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
9cc349fe-fa7f-47bd-84a2-4018344ac5ec	CLI-000149	hogar	karina	hernandez	CC1755787758	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 09:49:18.303677-05	2025-08-21 09:49:18.303677-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
1fff99c3-1c0d-446e-9c6c-a47e2b63a0fc	CLI-000150	hogar	karina	hernandez	CC1755790586	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 10:36:26.756822-05	2025-08-21 10:36:26.756822-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
f3b9503a-7ac0-41b9-92c8-edfc946d20f7	CLI-000151	hogar	Prueba	Roles	CC9999	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 12:19:29.026747-05	2025-08-21 12:19:29.026747-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
ea137b81-61e4-4ee7-9963-ecc3de25bd99	CLI-000152	hogar	Prueba	RBAC	CC184	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 14:34:32.693161-05	2025-08-21 14:34:32.693161-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
f77e2e5f-9088-44b7-b8e2-4ea730492f0d	CLI-000155	hogar	Prueba	RBAC	CC21324	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-21 15:09:48.404668-05	2025-08-21 15:09:48.404668-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
d070c040-bff0-4913-a3b4-6283d06ef698	CLI-000156	hogar	nelson	lopez	1032456009	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-27 11:27:44.664118-05	2025-08-27 11:27:44.664118-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
2062a0fd-4ae2-4a18-a52a-dc8dd5bc151a	CLI-000157	hogar	roberto	bolaños	123456789	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-27 14:59:17.835193-05	2025-08-27 14:59:17.835193-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
3810a8b7-cd11-400a-bec3-f647205e5c2f	CLI-000158	hogar	kevin	carrillo	12345678909	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-27 15:01:38.500801-05	2025-08-27 15:01:38.500801-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
62e1681e-b52b-4f6d-a027-012aefa8dd45	CLI-000159	hogar	ramon	ortega	1032456333	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-27 16:49:20.692432-05	2025-08-27 16:49:20.692432-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
8a2c3be1-f3ae-4b51-a59f-2218915cc7b7	CLI-000160	hogar	pedro	rolon	1032456779	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-27 17:05:43.6749-05	2025-08-27 17:05:43.6749-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
8683c95c-5eb5-44a2-88b5-57a68784f111	CLI-000161	hogar	pedro	alvarez	1032453333	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-28 10:30:33.043303-05	2025-08-28 10:30:33.043303-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
f607ce6f-8182-4607-b7ac-09208c42c6f6	CLI-000162	hogar	kevin	jaramillo	888888888	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-28 10:32:19.582283-05	2025-08-28 10:32:19.582283-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
78d51b62-a048-4ad1-a756-44a9cbae7911	CLI-000154	hogar	Otra	Prueba	CC18663	\N	\N	contratado	\N	\N	\N	\N	\N	2025-08-21 15:06:01.181935-05	2025-08-21 15:06:01.181935-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
87869bfa-5525-489b-96e0-365ebf3a0c63	CLI-000126	hogar	Carlos	Rojas	123456	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-13 20:34:36.128673-05	2025-08-13 20:34:36.128673-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
f4677737-9930-4da1-8e3d-194151a49116	CLI-000124	hogar	Luis	Pérez	9876543210	luis@mail.com	3007654321	instalado	\N	\N	\N	\N	\N	2025-08-13 19:36:54.169101-05	2025-08-13 19:36:54.169101-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
f73f34e8-02d8-4aa4-912b-524561ac7801	CLI-000128	hogar	Carlos	Rojas	CC123456	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-13 20:56:36.458547-05	2025-08-13 20:56:36.458547-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
946c277c-e557-4cbb-80ee-459c95aad637	CLI-000134	hogar	laura	gonzalez	123412	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-13 21:47:05.087219-05	2025-08-13 21:47:05.087219-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
7b70930b-4104-4ba0-a7b4-757932af4f0e	CLI-000153	hogar	Prueba	RBAC	CC3	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-21 15:06:01.14164-05	2025-08-21 15:06:01.14164-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
04363624-3b11-415f-b133-370e6375b322	CLI-000123	hogar	Ana	Gómez	1032456789	ana@mail.com	3001234567	instalado	\N	\N	\N	\N	\N	2025-08-13 19:36:54.169101-05	2025-08-13 19:36:54.169101-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
5c4e775c-a201-462b-8e1c-c049686ee698	CLI-000170	hogar	pepe	aguilar	4444444	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 17:01:51.41842-05	2025-08-29 17:01:51.41842-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
4bb257d7-24e2-4fc7-bc2f-741e9a634243	CLI-000165	hogar	ramon	lopez	66666	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 09:25:43.765431-05	2025-08-29 09:25:43.765431-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
c9b072ba-1cc1-4f7e-bd97-9a1be55582e4	CLI-000164	hogar	ruben	perez	5555	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 09:13:20.519892-05	2025-08-29 09:13:20.519892-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
58465a3e-b016-4418-ab83-95983406b638	CLI-000166	hogar	carmen	perez	7777	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 10:19:52.76437-05	2025-08-29 10:19:52.76437-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
fdcb1fd5-030e-4243-ba42-37ca0f8323de	CLI-000168	hogar	caro	perez	88888	\N	\N	nuevo	\N	\N	\N	\N	\N	2025-08-29 15:47:05.948292-05	2025-08-29 15:47:05.948292-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
1d456856-c9a4-4917-bd43-f574661c05f5	CLI-000167	hogar	pedro	ortega	8888	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 10:28:29.494077-05	2025-08-29 10:28:29.494077-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
9a9a03e2-a2d5-4901-ac75-5f7cdbd0ce1d	CLI-000169	hogar	caro	mena	888889	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-29 16:29:27.918134-05	2025-08-29 16:29:27.918134-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
809a6932-fbe0-46bb-80bd-2936dbfe235e	CLI-000163	hogar	pati	perez	999999	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-28 10:59:03.434292-05	2025-08-28 10:59:03.434292-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
8e1597e7-33c9-40c1-9100-141933812459	CLI-000171	hogar	jeremy	carrillo	99999999	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-30 12:34:01.146664-05	2025-08-30 12:34:01.146664-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
2ccf6866-66d6-4770-bc03-f468253646eb	CLI-000172	hogar	carlo	robles	33333333	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 08:27:18.376185-05	2025-08-31 08:27:18.376185-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
092c7229-0f4b-4a8d-b15f-a6af1116b8dd	CLI-000173	hogar	lois	perez	999999999	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 08:33:26.02262-05	2025-08-31 08:33:26.02262-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
b77e211b-fee3-42b5-914f-987d0268ca9c	CLI-000174	hogar	keny	herrera	66666666666	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 08:52:16.612437-05	2025-08-31 08:52:16.612437-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
30b18dd1-49cd-481a-9ab5-c13680c79ba1	CLI-000175	hogar	rio	cameron	5555555555	\N	34567898765	instalado	\N	\N	\N	\N	\N	2025-08-31 09:22:46.544158-05	2025-08-31 09:22:46.544158-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
e7dd5e37-8dff-4ba8-a1ad-7754cea78f95	CLI-000178	hogar	pedro	picapiedra	222222222	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 11:58:22.761064-05	2025-08-31 11:58:22.761064-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
68598d9c-a7bd-4a4a-be2e-f0391cdefb2d	CLI-000176	hogar	pepe	santos	777777777	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 10:04:09.721333-05	2025-08-31 10:04:09.721333-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
9753dadb-a51a-4e93-ac31-94a5ffe0365d	CLI-000177	hogar	tita	gomez	55555555555	\N	\N	instalado	\N	\N	\N	\N	\N	2025-08-31 11:15:01.207395-05	2025-08-31 11:15:01.207395-05	\N	\N	\N	\N	\N	\N	\N	\N	0.00
\.


--
-- Data for Name: usuarios_sistema; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.usuarios_sistema (id, email, password_hash, nombre, activo) FROM stdin;
dc733092-662a-41e6-abea-304fab09b121	admin@local	$2a$10$D74hlVWcMsg7pR8jqIXEnuTus8Kiuxs6S9qUacmQtcTyALXTWG44S	Administrador	t
bf01e076-b05f-415a-ac88-fe2a264b2c6a	tech@local	$2a$10$eanKLnd91pCLPpRIXYhOUOVW51rvBQ/5.uIU6/5fFIrLp5cyOuhxO	Técnico	t
\.


--
-- Data for Name: ventas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ventas (id, codigo, usuario_id, cliente_nombre, cliente_apellido, documento, total, estado, created_at, plan_codigo, incluye_tv, plan_nombre, plan_vel_mbps, plan_alta, plan_mensual, alta_costo, mensual_internet, mensual_tv, mensual_total, recibo_pdf_key, contrato_pdf_key, recibo_img_key, cedula_img_key, firma_img_key) FROM stdin;
c6a0f70c-e19b-4b37-9888-af4717d3c18c	VEN-000002	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	30.00	pagada	2025-08-13 20:00:12.292343-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
497c33e0-aee0-461d-a988-9aa7d731e8ac	VEN-000003	f4677737-9930-4da1-8e3d-194151a49116	Luis	Pérez	9876543210	30.00	pagada	2025-08-13 20:26:55.609783-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
418fb892-7e4d-4a48-a176-a6636e960ae7	VEN-000006	f73f34e8-02d8-4aa4-912b-524561ac7801	Carlos	Rojas	CC123456	30.00	pagada	2025-08-13 20:56:36.463686-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
de0a2221-e09b-4258-8afe-877a2e07652f	VEN-000008	af9a5f66-b5d5-4a10-aa5c-71dee7793ef6	nervin	suarez	CC123457	30.00	pagada	2025-08-13 21:02:25.219719-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
fbb47ea4-f316-43e8-8b14-5c42d7fb43c8	VEN-000009	d2d81a5d-728b-4d13-9c22-177b3e7989b8	kevin	carrillo	CC123458	30.00	pagada	2025-08-13 21:07:20.336197-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
91eac6ea-ed4f-4938-bebc-b9b4433db800	VEN-000010	e9cd2fb6-45ae-4117-a7cc-d606593740d8	ramon	valdes	CC123410	30.00	pagada	2025-08-13 21:29:42.922294-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
1a5a2b3a-5e62-43e0-80ce-aeaca5a0e5f7	VEN-000011	827d0471-2d76-4bbe-a364-93081992a32e	Pedro	Rolon	CC123411	30.00	pagada	2025-08-13 21:40:23.831213-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
06582703-d5d9-4d04-9b1c-8fcd6ca0ad79	VEN-000013	f73f34e8-02d8-4aa4-912b-524561ac7801	carla	gonzalez	CC123456	30.00	pagada	2025-08-13 21:47:36.596319-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
e842d716-251a-42ff-bf98-ad4a07ae7b46	VEN-000014	588f3ddc-cc2d-4b58-a9e4-3c84bc032827	roberto	Rojas	CC123413	30.00	pagada	2025-08-13 22:02:16.466495-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
5ebcb3ea-85c1-4f10-9a59-bba44dec8c75	VEN-000015	d76407e1-e4ef-4a22-b216-336c792ce61a	pedro	Rojas	CC123415	30.00	pagada	2025-08-13 22:03:51.41916-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
8f704aca-55e2-4f50-8dc4-3a1640299bac	VEN-000016	96bf6d92-061b-409e-bc4a-86d30edc1a10	Demo	Tecnico	CC000	30.00	pagada	2025-08-14 10:39:43.686678-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
0238fb34-3d87-4333-8ee7-8559e26585bc	VEN-000017	0ee9864a-d7f7-46a6-b53c-9f4d0c1a229a	Demo	Tecnico	CC999	30.00	pagada	2025-08-14 14:03:53.614778-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
b2cf6533-ead2-45d9-bf11-c4d08681ec73	VEN-000018	e5b878ab-50d9-416f-be07-b5cb27534193	jorge	mandon	CC-456732	30.00	pagada	2025-08-14 15:37:02.55032-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
42fd4c8b-bfb6-407f-ba94-bd9eba553d73	VEN-000019	04e35388-a50d-4d55-a5fc-3521b54b6e68	pedro	alvarez	CC9945	30.00	pagada	2025-08-14 15:51:16.189513-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
9a3f1290-6d43-418d-9e2c-b8a4fe33d041	VEN-000020	74986c44-4c01-45b5-90b3-e4cfb2dfb5eb	ramon	caldera	CC3459	30.00	pagada	2025-08-14 15:59:07.982284-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
e3050916-970b-4eb6-93e7-2e65f3fcc401	VEN-000021	0ee9864a-d7f7-46a6-b53c-9f4d0c1a229a	carlos	torres	CC999	30.00	pagada	2025-08-19 11:35:05.491519-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
a79042da-69f2-48af-8a55-3a33686baf56	VEN-000022	5ee1a37f-ab38-4513-bbb1-690b51caf81f	Test	Tecnico	CC-DEMO	30.00	pagada	2025-08-19 11:58:24.759226-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
f02fe6de-fcd1-4570-ac7c-5be9e437a62d	VEN-000023	5ee1a37f-ab38-4513-bbb1-690b51caf81f	Test	Tecnico	CC-DEMO	30.00	pagada	2025-08-19 11:58:54.458644-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
2c192569-fcc1-4021-99d7-d4c11ce0fcbd	VEN-000024	5ee1a37f-ab38-4513-bbb1-690b51caf81f	Test	Tecnico	CC-DEMO	30.00	pagada	2025-08-20 11:15:12.817337-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
a147f816-1794-4b28-9ed4-5d02a4d9945e	VEN-000025	7a9585d7-fe29-4c6d-b3a6-9c80a935124c	pedro	gonzalez	CC7894	30.00	pagada	2025-08-20 16:22:59.322246-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
e08bfe79-fbd0-4e4d-bc1a-432dd4ce07d3	VEN-000026	7ce89f8c-cc2e-4fd0-9695-8a1184c39b0d	karina	hernandez	CC7854	30.00	pagada	2025-08-21 09:25:10.640022-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
fdff628b-6bf5-4676-8b5f-16f1e6e0f58f	VEN-000027	9cc349fe-fa7f-47bd-84a2-4018344ac5ec	karina	hernandez	CC1755787758	30.00	pagada	2025-08-21 09:49:18.308523-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
68d63b55-8088-4cf6-a4a8-28c67d3f3971	VEN-000028	1fff99c3-1c0d-446e-9c6c-a47e2b63a0fc	karina	hernandez	CC1755790586	30.00	pagada	2025-08-21 10:36:26.762035-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
aec97267-509a-4758-823c-5d76eb3c09f5	VEN-000030	78d51b62-a048-4ad1-a756-44a9cbae7911	Otra	Prueba	CC18663	30.00	pagada	2025-08-21 15:06:01.18694-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
1a885937-a630-4d9e-893f-ffafcf715c74	VEN-000031	f77e2e5f-9088-44b7-b8e2-4ea730492f0d	Prueba	RBAC	CC21324	30.00	pagada	2025-08-21 15:09:48.410377-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
f401c37b-04f3-41c0-aa14-aae646ab122c	VEN-000033	d070c040-bff0-4913-a3b4-6283d06ef698	nelson	lopez	1032456009	30.00	pagada	2025-08-27 11:27:44.670702-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
ab1c5556-8839-4871-a7f7-da956f442489	VEN-000034	2062a0fd-4ae2-4a18-a52a-dc8dd5bc151a	roberto	bolaños	123456789	30.00	pagada	2025-08-27 14:59:17.840675-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
dcd81030-fd9a-4739-9b8e-0c20aca4351d	VEN-000035	3810a8b7-cd11-400a-bec3-f647205e5c2f	kevin	carrillo	12345678909	30.00	pagada	2025-08-27 15:01:38.506806-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
77e62395-e1b8-42e0-92f4-c202ebc42ff8	VEN-000036	62e1681e-b52b-4f6d-a027-012aefa8dd45	ramon	ortega	1032456333	30.00	pagada	2025-08-27 16:49:20.708515-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
67b42cb3-01e7-49b5-851e-87ed37ab4ee8	VEN-000038	8a2c3be1-f3ae-4b51-a59f-2218915cc7b7	pedro	rolon	1032456779	30.00	pagada	2025-08-27 17:05:43.682804-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
2a733814-8ac7-4c04-8bb7-35c2a328e955	VEN-000039	8683c95c-5eb5-44a2-88b5-57a68784f111	pedro	alvarez	1032453333	30.00	pagada	2025-08-28 10:30:33.060375-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
a2e7a5b6-103c-4ae3-bdfc-18b23d1b331f	VEN-000040	f607ce6f-8182-4607-b7ac-09208c42c6f6	kevin	jaramillo	888888888	30.00	pagada	2025-08-28 10:32:19.588471-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
76ddc7f0-0438-4ceb-8405-1aceb9d28d9c	VEN-000042	809a6932-fbe0-46bb-80bd-2936dbfe235e	carlos	carrillo	999999	100.00	pagada	2025-08-28 15:04:37.195261-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
4028845f-9093-4e17-92ad-3077f806e598	VEN-000041	809a6932-fbe0-46bb-80bd-2936dbfe235e	pati	perez	999999	100.00	pagada	2025-08-28 10:59:03.439842-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
3dac3154-8c54-4f55-85b6-c827cc8fbd1c	VEN-000037	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	30.00	pagada	2025-08-27 17:04:22.454444-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
3c257c76-674e-49ba-af33-51e343a9718e	VEN-000029	7b70930b-4104-4ba0-a7b4-757932af4f0e	Prueba	RBAC	CC3	30.00	pagada	2025-08-21 15:06:01.15751-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
f1f3dcdc-d884-4674-a74e-bd1fa33f02c8	VEN-000032	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	30.00	pagada	2025-08-27 11:26:50.600355-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
05566472-e8ca-4015-bd2e-658990a7cad7	VEN-000012	946c277c-e557-4cbb-80ee-459c95aad637	laura	gonzalez	123412	30.00	pagada	2025-08-13 21:47:05.091841-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
9053e99c-7fa9-4e8f-8dc7-67edf9c73350	VEN-000007	f73f34e8-02d8-4aa4-912b-524561ac7801	Carlos	Rojas	CC123456	30.00	pagada	2025-08-13 21:01:06.676543-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
74d1746e-ff84-49e4-a960-e5d28d54e7e6	VEN-000005	f4677737-9930-4da1-8e3d-194151a49116	Luis	Pérez	9876543210	30.00	pagada	2025-08-13 20:52:11.908145-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
c6fbdd1d-9f13-4395-9421-9d857f1bfd89	VEN-000004	87869bfa-5525-489b-96e0-365ebf3a0c63	Carlos	Rojas	123456	30.00	pagada	2025-08-13 20:34:36.141301-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
0b748ec5-b818-4e9b-94ed-b60b1ee4de21	VEN-000001	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	30.00	pagada	2025-08-13 19:53:41.955807-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
af609173-efb9-49e4-9307-5f74b4a2091b	VEN-000043	c9b072ba-1cc1-4f7e-bd97-9a1be55582e4	ruben	perez	5555	100.00	pagada	2025-08-29 09:13:20.536693-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
5d230654-dc84-4d3c-8c57-6fa7c0a66617	VEN-000044	4bb257d7-24e2-4fc7-bc2f-741e9a634243	ramon	lopez	66666	100.00	pagada	2025-08-29 09:25:43.773001-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
2856fc50-fa19-4b59-bf0b-b82c122f9ae1	VEN-000045	58465a3e-b016-4418-ab83-95983406b638	carmen	perez	7777	1000.00	pagada	2025-08-29 10:19:52.771177-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
0c13ebb8-1b64-4243-94a5-871c6e8cc35f	VEN-000046	1d456856-c9a4-4917-bd43-f574661c05f5	pedro	ortega	8888	888888.00	pagada	2025-08-29 10:28:29.500235-05	\N	f	\N	\N	0.00	0.00	0.00	0.00	0.00	0.00	\N	\N	\N	\N	\N
daeeaae6-b1c8-4e2d-bd4f-f6768031d6b4	VEN-000047	1d456856-c9a4-4917-bd43-f574661c05f5	Caro	Pabon	8888	80000.00	pagada	2025-08-29 16:39:02.459807-05	INT-200	t	Internet 200M	200	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000047/recibo.pdf	ventas/VEN-000047/contrato.pdf	\N	\N	\N
50ce0a58-233c-425f-ab36-704054ef3393	VEN-000048	9a9a03e2-a2d5-4901-ac75-5f7cdbd0ce1d	caro	mena	888889	80000.00	pagada	2025-08-29 16:39:29.070419-05	INT-200	t	Internet 200M	200	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000048/recibo.pdf	ventas/VEN-000048/contrato.pdf	\N	\N	\N
b998502a-5b21-4889-b830-21eec2559b34	VEN-000049	809a6932-fbe0-46bb-80bd-2936dbfe235e	pepe	aguilar	999999	80000.00	pagada	2025-08-29 16:58:25.592499-05	INT-300	t	Internet 300M	300	0.00	0.00	80000.00	60000.00	30000.00	90000.00	ventas/VEN-000049/recibo.pdf	ventas/VEN-000049/contrato.pdf	\N	\N	\N
4608919d-8126-43d1-8e90-9b452a7ea9cb	VEN-000050	809a6932-fbe0-46bb-80bd-2936dbfe235e	pepe	aguilar	999999	80000.00	pagada	2025-08-29 17:00:13.695703-05	INT-300	t	Internet 300M	300	0.00	0.00	80000.00	60000.00	30000.00	90000.00	ventas/VEN-000050/recibo.pdf	ventas/VEN-000050/contrato.pdf	\N	\N	\N
5f5e6061-b2a0-4791-a7ed-af1bfe3043f3	VEN-000051	5c4e775c-a201-462b-8e1c-c049686ee698	pepe	aguilar	4444444	80000.00	pagada	2025-08-29 17:01:51.426773-05	INT-500	t	Internet 500M	500	0.00	0.00	80000.00	90000.00	30000.00	120000.00	ventas/VEN-000051/recibo.pdf	ventas/VEN-000051/contrato.pdf	\N	\N	\N
c7e1433a-a34f-43f8-9f62-70f817f631c7	VEN-000052	8e1597e7-33c9-40c1-9100-141933812459	jeremy	carrillo	99999999	80000.00	pagada	2025-08-30 12:34:01.160332-05	INT-200	t	Internet 200M	200	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000052/recibo.pdf	ventas/VEN-000052/contrato.pdf	\N	\N	\N
f5e7a627-45b7-4673-b468-1ca5e2d18eb6	VEN-000053	2ccf6866-66d6-4770-bc03-f468253646eb	carlo	robles	33333333	0.00	pagada	2025-08-31 08:27:18.391148-05	INT-003	f	Hogar 100	0	0.00	0.00	0.00	0.00	0.00	0.00	ventas/VEN-000053/recibo.pdf	ventas/VEN-000053/contrato.pdf	\N	\N	\N
58608052-2db1-49c7-92d8-de63f82c9513	VEN-000054	092c7229-0f4b-4a8d-b15f-a6af1116b8dd	lois	perez	999999999	80000.00	pagada	2025-08-31 08:33:26.029054-05	INT-200	t	Internet 200M	200	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000054/recibo.pdf	ventas/VEN-000054/contrato.pdf	\N	\N	\N
bcf420e9-5de4-4f6a-9730-904c0047f3bb	VEN-000066	98480b51-b943-4cc4-8aad-97df7d36c9ef	carlos	perez	11111111	80000.00	pagada	2025-08-31 12:29:29.077895-05	INT-500	t	Internet 500M	\N	0.00	0.00	80000.00	90000.00	30000.00	120000.00	evidencias/ventas/VEN-000066/recibo.pdf	evidencias/ventas/VEN-000066/contrato.pdf	\N	\N	\N
060e9793-7a83-4143-ae42-863ab77b03ac	VEN-000055	b77e211b-fee3-42b5-914f-987d0268ca9c	keny	herrera	66666666666	80000.00	pagada	2025-08-31 08:52:16.618475-05	INT-200	t	Internet 200M	200	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000055/recibo.pdf	ventas/VEN-000055/contrato.pdf	\N	\N	\N
27bfe543-e877-4bb2-b140-bbf069ba3f17	VEN-000056	30b18dd1-49cd-481a-9ab5-c13680c79ba1	rio	cameron	5555555555	80000.00	pagada	2025-08-31 09:22:46.559712-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000056/recibo.pdf	ventas/VEN-000056/contrato.pdf	\N	\N	\N
2421492b-9d93-4e5b-89c7-7e5226104341	VEN-000057	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 09:53:24.146673-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	evidencias/ventas/VEN-000057/recibo.pdf	evidencias/ventas/VEN-000057/contrato.pdf	\N	\N	\N
40de531f-074d-41a0-b3fb-ca1d4b316a27	VEN-000067	bad773a4-fb71-4b8f-a61c-dccf31fe5e5e	lamine	yamale	77777777	80000.00	pagada	2025-08-31 15:59:50.816756-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	evidencias/ventas/VEN-000067/recibo.pdf	evidencias/ventas/VEN-000067/contrato.pdf	\N	\N	\N
d42725c7-ef52-4a9c-b264-262c2407f0a5	VEN-000058	68598d9c-a7bd-4a4a-be2e-f0391cdefb2d	pepe	santos	777777777	80000.00	pagada	2025-08-31 10:04:09.729232-05	INT-500	t	Internet 500M	\N	0.00	0.00	80000.00	90000.00	30000.00	120000.00	evidencias/ventas/VEN-000058/recibo.pdf	evidencias/ventas/VEN-000058/contrato.pdf	\N	\N	\N
877b5ced-35fc-4b1a-b352-45ab1706d051	VEN-000060	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 11:09:01.215207-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000060/recibo.pdf	ventas/VEN-000060/contrato.pdf	\N	\N	\N
86876131-ce2e-426a-a047-1a11fc871e63	VEN-000061	9753dadb-a51a-4e93-ac31-94a5ffe0365d	tita	gomez	55555555555	80000.00	pagada	2025-08-31 11:15:01.214848-05	INT-300	t	Internet 300M	\N	0.00	0.00	80000.00	60000.00	30000.00	90000.00	ventas/VEN-000061/recibo.pdf	ventas/VEN-000061/contrato.pdf	\N	\N	\N
85dfc3e5-ee65-4fc5-9333-5dbe790e6cd5	VEN-000068	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 16:09:01.771826-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	evidencias/ventas/VEN-000068/recibo.pdf	evidencias/ventas/VEN-000068/contrato.pdf	\N	\N	\N
5faff5f2-2094-4d86-a2cd-9182ef21d72f	VEN-000062	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 11:54:19.053065-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000062/recibo.pdf	ventas/VEN-000062/contrato.pdf	\N	\N	\N
bb1fdfbb-2524-4f6c-9fed-3c90b22524a9	VEN-000059	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 11:02:02.850891-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	ventas/VEN-000059/recibo.pdf	ventas/VEN-000059/contrato.pdf	\N	\N	\N
aed4f84b-7b9e-4ad0-a951-cde69a4a55de	VEN-000063	e7dd5e37-8dff-4ba8-a1ad-7754cea78f95	pedro	picapiedra	222222222	80000.00	pagada	2025-08-31 11:58:22.7672-05	INT-500	t	Internet 500M	\N	0.00	0.00	80000.00	90000.00	30000.00	120000.00	ventas/VEN-000063/recibo.pdf	ventas/VEN-000063/contrato.pdf	\N	\N	\N
cb741f0d-afe8-4fb7-8eeb-5845f3455609	VEN-000064	04363624-3b11-415f-b133-370e6375b322	Ana	Gómez	1032456789	80000.00	pagada	2025-08-31 12:17:15.013589-05	INT-200	t	Internet 200M	\N	0.00	0.00	80000.00	50000.00	30000.00	80000.00	evidencias/ventas/VEN-000064/recibo.pdf	evidencias/ventas/VEN-000064/contrato.pdf	\N	\N	\N
a8f64020-6bc9-4a98-8038-466fe0dedb02	VEN-000065	e7dd5e37-8dff-4ba8-a1ad-7754cea78f95	vanesa	pineda	222222222	80000.00	pagada	2025-08-31 12:19:20.231562-05	INT-500	t	Internet 500M	\N	0.00	0.00	80000.00	90000.00	30000.00	120000.00	evidencias/ventas/VEN-000065/recibo.pdf	evidencias/ventas/VEN-000065/contrato.pdf	\N	\N	\N
\.


--
-- Data for Name: vias; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.vias (id, codigo, nombre, activo) FROM stdin;
23014a2d-3c1c-4412-ae6c-13854ee9f59f	CALLE	CALLE	t
9161982e-6ef1-4638-98dd-42d306854134	CARRERA	CARRERA	t
56a2e429-21e9-4de8-8dda-553723fbd0d3	DIAGONAL	DIAGONAL	t
69d3377e-d183-4cb6-bef5-56272176ea18	TRANSVERSAL	TRANSVERSAL	t
310ebec7-08f0-4a0b-a608-cb009d62a8f6	AVENIDA	AVENIDA	t
\.


--
-- Data for Name: zonas; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.zonas (id, nombre) FROM stdin;
1086dd29-6bed-454b-ae03-9500a9427666	Zona Centro
0f13400f-6261-4509-8b34-4daed05ffdae	Zona Norte
24c4491f-e10c-4a2c-a930-fd470dd642b7	Zona Sur
\.


--
-- Name: ventas_codigo_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ventas_codigo_seq', 1, false);


--
-- Name: agentes agentes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agentes
    ADD CONSTRAINT agentes_pkey PRIMARY KEY (id);


--
-- Name: app_users app_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_pkey PRIMARY KEY (id);


--
-- Name: app_users app_users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_username_key UNIQUE (username);


--
-- Name: auditoria auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id);


--
-- Name: barrios barrios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barrios
    ADD CONSTRAINT barrios_pkey PRIMARY KEY (id);


--
-- Name: cierres_contables cierres_contables_periodo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cierres_contables
    ADD CONSTRAINT cierres_contables_periodo_key UNIQUE (periodo);


--
-- Name: cierres_contables cierres_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cierres_contables
    ADD CONSTRAINT cierres_contables_pkey PRIMARY KEY (id);


--
-- Name: ciudades ciudades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ciudades
    ADD CONSTRAINT ciudades_pkey PRIMARY KEY (id);


--
-- Name: evidencias evidencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidencias
    ADD CONSTRAINT evidencias_pkey PRIMARY KEY (id);


--
-- Name: factura_detalle factura_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_detalle
    ADD CONSTRAINT factura_detalle_pkey PRIMARY KEY (id);


--
-- Name: facturas facturas_numero_fiscal_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_numero_fiscal_key UNIQUE (numero_fiscal);


--
-- Name: facturas facturas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_pkey PRIMARY KEY (id);


--
-- Name: inventario_equipos inventario_equipos_mac_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_equipos
    ADD CONSTRAINT inventario_equipos_mac_key UNIQUE (mac);


--
-- Name: inventario_equipos inventario_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_equipos
    ADD CONSTRAINT inventario_equipos_pkey PRIMARY KEY (id);


--
-- Name: inventario_equipos inventario_equipos_serie_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_equipos
    ADD CONSTRAINT inventario_equipos_serie_key UNIQUE (serie);


--
-- Name: inventario_materiales inventario_materiales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_materiales
    ADD CONSTRAINT inventario_materiales_pkey PRIMARY KEY (id);


--
-- Name: mov_inventario mov_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mov_inventario
    ADD CONSTRAINT mov_inventario_pkey PRIMARY KEY (id);


--
-- Name: municipios municipios_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipios
    ADD CONSTRAINT municipios_codigo_key UNIQUE (codigo);


--
-- Name: municipios municipios_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipios
    ADD CONSTRAINT municipios_nombre_key UNIQUE (nombre);


--
-- Name: municipios municipios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipios
    ADD CONSTRAINT municipios_pkey PRIMARY KEY (id);


--
-- Name: notas_credito notas_credito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notas_credito
    ADD CONSTRAINT notas_credito_pkey PRIMARY KEY (id);


--
-- Name: ordenes ordenes_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_codigo_key UNIQUE (codigo);


--
-- Name: ordenes ordenes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_pkey PRIMARY KEY (id);


--
-- Name: ordenes_servicio ordenes_servicio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes_servicio
    ADD CONSTRAINT ordenes_servicio_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: paises paises_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.paises
    ADD CONSTRAINT paises_pkey PRIMARY KEY (id);


--
-- Name: permisos permisos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permisos
    ADD CONSTRAINT permisos_pkey PRIMARY KEY (id);


--
-- Name: planes planes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT planes_pkey PRIMARY KEY (id);


--
-- Name: rol_permisos rol_permisos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT rol_permisos_pkey PRIMARY KEY (rol_id, permiso_id);


--
-- Name: roles roles_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_nombre_key UNIQUE (nombre);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: sectores sectores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sectores
    ADD CONSTRAINT sectores_pkey PRIMARY KEY (id);


--
-- Name: smartolt_logs smartolt_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.smartolt_logs
    ADD CONSTRAINT smartolt_logs_pkey PRIMARY KEY (id);


--
-- Name: tarifas tarifas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tarifas
    ADD CONSTRAINT tarifas_pkey PRIMARY KEY (id);


--
-- Name: tecnicos tecnicos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tecnicos
    ADD CONSTRAINT tecnicos_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: sectores uniq_sectores_mun_zona_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sectores
    ADD CONSTRAINT uniq_sectores_mun_zona_nombre UNIQUE (municipio_codigo, zona, nombre);


--
-- Name: planes uq_planes_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT uq_planes_codigo UNIQUE (codigo);


--
-- Name: usuario_roles usuario_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT usuario_roles_pkey PRIMARY KEY (usuario_id, rol_id);


--
-- Name: usuarios usuarios_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_codigo_key UNIQUE (codigo);


--
-- Name: usuarios usuarios_documento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_documento_key UNIQUE (documento);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: usuarios_sistema usuarios_sistema_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_sistema
    ADD CONSTRAINT usuarios_sistema_email_key UNIQUE (email);


--
-- Name: usuarios_sistema usuarios_sistema_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_sistema
    ADD CONSTRAINT usuarios_sistema_pkey PRIMARY KEY (id);


--
-- Name: ventas ventas_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_codigo_key UNIQUE (codigo);


--
-- Name: ventas ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_pkey PRIMARY KEY (id);


--
-- Name: vias vias_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vias
    ADD CONSTRAINT vias_codigo_key UNIQUE (codigo);


--
-- Name: vias vias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vias
    ADD CONSTRAINT vias_pkey PRIMARY KEY (id);


--
-- Name: zonas zonas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zonas
    ADD CONSTRAINT zonas_pkey PRIMARY KEY (id);


--
-- Name: idx_evidencias_orden; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_evidencias_orden ON public.evidencias USING btree (orden_id);


--
-- Name: idx_facturas_usuario_periodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_facturas_usuario_periodo ON public.facturas USING btree (usuario_id, periodo);


--
-- Name: idx_ordenes_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ordenes_codigo ON public.ordenes USING btree (codigo);


--
-- Name: idx_smartolt_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_smartolt_request ON public.smartolt_logs USING btree (request_id);


--
-- Name: idx_usuarios_busqueda; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuarios_busqueda ON public.usuarios USING btree (codigo, documento, apellido);


--
-- Name: idx_usuarios_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usuarios_estado ON public.usuarios USING btree (estado);


--
-- Name: idx_ventas_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ventas_codigo ON public.ventas USING btree (codigo);


--
-- Name: auditoria auditoria_usuario_sistema_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_usuario_sistema_id_fkey FOREIGN KEY (usuario_sistema_id) REFERENCES public.usuarios_sistema(id);


--
-- Name: barrios barrios_ciudad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.barrios
    ADD CONSTRAINT barrios_ciudad_id_fkey FOREIGN KEY (ciudad_id) REFERENCES public.ciudades(id);


--
-- Name: ciudades ciudades_pais_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ciudades
    ADD CONSTRAINT ciudades_pais_id_fkey FOREIGN KEY (pais_id) REFERENCES public.paises(id);


--
-- Name: factura_detalle factura_detalle_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_detalle
    ADD CONSTRAINT factura_detalle_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id);


--
-- Name: factura_detalle factura_detalle_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.factura_detalle
    ADD CONSTRAINT factura_detalle_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.planes(id);


--
-- Name: facturas facturas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: inventario_equipos inventario_equipos_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_equipos
    ADD CONSTRAINT inventario_equipos_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id);


--
-- Name: inventario_equipos inventario_equipos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventario_equipos
    ADD CONSTRAINT inventario_equipos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: mov_inventario mov_inventario_equipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mov_inventario
    ADD CONSTRAINT mov_inventario_equipo_id_fkey FOREIGN KEY (equipo_id) REFERENCES public.inventario_equipos(id);


--
-- Name: mov_inventario mov_inventario_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mov_inventario
    ADD CONSTRAINT mov_inventario_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.inventario_materiales(id);


--
-- Name: mov_inventario mov_inventario_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mov_inventario
    ADD CONSTRAINT mov_inventario_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes_servicio(id);


--
-- Name: notas_credito notas_credito_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notas_credito
    ADD CONSTRAINT notas_credito_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id);


--
-- Name: ordenes_servicio ordenes_servicio_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes_servicio
    ADD CONSTRAINT ordenes_servicio_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id);


--
-- Name: ordenes_servicio ordenes_servicio_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes_servicio
    ADD CONSTRAINT ordenes_servicio_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: ordenes_servicio ordenes_servicio_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ordenes_servicio
    ADD CONSTRAINT ordenes_servicio_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: pagos pagos_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id);


--
-- Name: pagos pagos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: rol_permisos rol_permisos_permiso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT rol_permisos_permiso_id_fkey FOREIGN KEY (permiso_id) REFERENCES public.permisos(id);


--
-- Name: rol_permisos rol_permisos_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT rol_permisos_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roles(id);


--
-- Name: sectores sectores_municipio_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sectores
    ADD CONSTRAINT sectores_municipio_codigo_fkey FOREIGN KEY (municipio_codigo) REFERENCES public.municipios(codigo) ON UPDATE CASCADE;


--
-- Name: tarifas tarifas_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tarifas
    ADD CONSTRAINT tarifas_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.planes(id);


--
-- Name: tickets tickets_operador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_operador_id_fkey FOREIGN KEY (operador_id) REFERENCES public.agentes(id);


--
-- Name: tickets tickets_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id);


--
-- Name: usuario_roles usuario_roles_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT usuario_roles_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roles(id);


--
-- Name: usuario_roles usuario_roles_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT usuario_roles_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios_sistema(id);


--
-- Name: usuarios usuarios_barrio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_barrio_id_fkey FOREIGN KEY (barrio_id) REFERENCES public.barrios(id);


--
-- Name: usuarios usuarios_ciudad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_ciudad_id_fkey FOREIGN KEY (ciudad_id) REFERENCES public.ciudades(id);


--
-- Name: usuarios usuarios_municipio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipios(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict Bl7CMsidO5aXZQytZBNEijzGARPHcRcKhdQKwKCx9VtlkyHFMJCY5t55wua5IOK

