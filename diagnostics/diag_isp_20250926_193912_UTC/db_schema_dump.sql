--
-- PostgreSQL database dump
--

\restrict j1njRIl1sgTX815j0JTSaY7AptLMQfZvGdOm81rEaP8TaYkLo6KWvyr6tTQVCya

-- Dumped from database version 14.19
-- Dumped by pg_dump version 14.19

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
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: orden_evento_tipo; Type: TYPE; Schema: public; Owner: ispuser
--

CREATE TYPE public.orden_evento_tipo AS ENUM (
    'iniciar',
    'cerrar',
    'asignar',
    'reagendar',
    'cancelar',
    'anular'
);


ALTER TYPE public.orden_evento_tipo OWNER TO ispuser;

--
-- Name: usuario_estado; Type: TYPE; Schema: public; Owner: ispuser
--

CREATE TYPE public.usuario_estado AS ENUM (
    'nuevo',
    'contratado',
    'instalado',
    'desconectado',
    'terminado'
);


ALTER TYPE public.usuario_estado OWNER TO ispuser;

--
-- Name: usuario_estado_conexion; Type: TYPE; Schema: public; Owner: ispuser
--

CREATE TYPE public.usuario_estado_conexion AS ENUM (
    'conectado',
    'desconectado'
);


ALTER TYPE public.usuario_estado_conexion OWNER TO ispuser;

--
-- Name: f_ordenes_after_update_rec(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.f_ordenes_after_update_rec() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Dispara sólo si el estado cambió y quedó 'cerrada'
  IF TG_OP = 'UPDATE'
     AND NEW.tipo = 'REC'
     AND NEW.estado = 'cerrada'
     AND (OLD.estado IS DISTINCT FROM NEW.estado)
  THEN
    UPDATE usuarios
       SET estado_conexion = 'conectado',
           updated_at = now()
     WHERE id = NEW.usuario_id;
  END IF;
  RETURN NEW;
END
$$;


ALTER FUNCTION public.f_ordenes_after_update_rec() OWNER TO ispuser;

--
-- Name: fn_log_orden_eventos(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_log_orden_eventos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Evento INICIAR (solo si cambió iniciada_at)
  IF NEW.iniciada_at IS NOT NULL
     AND (OLD.iniciada_at IS NULL OR NEW.iniciada_at <> OLD.iniciada_at) THEN
    INSERT INTO orden_eventos (orden_id, tecnico_id, tipo, payload, created_at)
    VALUES (
      NEW.id,
      NEW.tecnico_id,
      'iniciar'::orden_evento_tipo,
      jsonb_build_object(
        'fuente','trigger',
        'codigo', NEW.codigo,
        'estado', NEW.estado
      ),
      COALESCE(NEW.iniciada_at, now())
    );
  END IF;

  -- Evento CERRAR (solo si cambió cerrada_at)
  IF NEW.cerrada_at IS NOT NULL
     AND (OLD.cerrada_at IS NULL OR NEW.cerrada_at <> OLD.cerrada_at) THEN
    INSERT INTO orden_eventos (orden_id, tecnico_id, tipo, payload, created_at)
    VALUES (
      NEW.id,
      NEW.tecnico_id,
      'cerrar'::orden_evento_tipo,
      jsonb_build_object(
        'fuente','trigger',
        'codigo', NEW.codigo,
        'estado', NEW.estado,
        'cierre_token', NEW.cierre_token
      ),
      COALESCE(NEW.cerrada_at, now())
    );
  END IF;

  RETURN NEW;
END $$;


ALTER FUNCTION public.fn_log_orden_eventos() OWNER TO ispuser;

--
-- Name: inv_tecnico_merge(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.inv_tecnico_merge() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM inv_tecnico it WHERE it.tecnico_id=NEW.tecnico_id AND it.material_id=NEW.material_id) THEN
    UPDATE inv_tecnico it
    SET cantidad = COALESCE(it.cantidad,0) + COALESCE(NEW.cantidad,0)
    WHERE it.tecnico_id=NEW.tecnico_id AND it.material_id=NEW.material_id;
    RETURN NULL;
  END IF;
  RETURN NEW;
END; $$;


ALTER FUNCTION public.inv_tecnico_merge() OWNER TO ispuser;

--
-- Name: om_material_id_default(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.om_material_id_default() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- En INSERT: si viene NULL o no viene, genera UUID
  IF TG_OP = 'INSERT' THEN
    NEW.material_id := COALESCE(NEW.material_id, gen_random_uuid());
    RETURN NEW;
  END IF;

  -- En UPDATE (incluye ON CONFLICT DO UPDATE):
  -- Si NEW.material_id es NULL, conserva el OLD.material_id (si existe),
  -- o genera uno nuevo si por algún motivo tampoco existe.
  IF TG_OP = 'UPDATE' THEN
    NEW.material_id := COALESCE(NEW.material_id, OLD.material_id, gen_random_uuid());
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.om_material_id_default() OWNER TO ispuser;

--
-- Name: om_material_id_merge(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.om_material_id_merge() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Siempre garantizamos NEW.material_id no nulo
    NEW.material_id := COALESCE(NEW.material_id, gen_random_uuid());

    -- Si ya existe el par (orden_id, material_id_int) => MERGE (sumar) y NO cambies material_id
    IF EXISTS (
      SELECT 1
      FROM orden_materiales om
      WHERE om.orden_id = NEW.orden_id
        AND om.material_id_int = NEW.material_id_int
    ) THEN
      UPDATE orden_materiales om
      SET cantidad  = om.cantidad + COALESCE(NEW.cantidad, 0),
          -- material_id se conserva como está (no lo tocamos)
          descontado = (COALESCE(NEW.descontado, FALSE) OR COALESCE(om.descontado, FALSE))
      WHERE om.orden_id = NEW.orden_id
        AND om.material_id_int = NEW.material_id_int;

      RETURN NULL; -- se evita el INSERT (ya hicimos UPDATE)
    END IF;

    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- En UPDATE solo garantizamos no nulo si llegara NULL
    NEW.material_id := COALESCE(NEW.material_id, OLD.material_id, gen_random_uuid());
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.om_material_id_merge() OWNER TO ispuser;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO ispuser;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_users; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.app_users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    username character varying(80) NOT NULL,
    pass_hash text NOT NULL,
    roles text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.app_users OWNER TO ispuser;

--
-- Name: cargos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.cargos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usuario_id uuid NOT NULL,
    orden_id uuid NOT NULL,
    concepto text NOT NULL,
    monto numeric(14,2) DEFAULT 0 NOT NULL,
    creado_at timestamp with time zone DEFAULT now() NOT NULL,
    aplicado boolean DEFAULT false NOT NULL
);


ALTER TABLE public.cargos OWNER TO ispuser;

--
-- Name: catalogo_items; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_items (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    orden smallint,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    catalogo_id uuid
);


ALTER TABLE public.catalogo_items OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_motivos_reagenda (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    orden integer
);


ALTER TABLE public.catalogo_motivos_reagenda OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda_api; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.catalogo_motivos_reagenda_api AS
 SELECT catalogo_motivos_reagenda.id,
    catalogo_motivos_reagenda.codigo AS code,
    catalogo_motivos_reagenda.nombre AS label
   FROM public.catalogo_motivos_reagenda
  WHERE (catalogo_motivos_reagenda.activo = true);


ALTER TABLE public.catalogo_motivos_reagenda_api OWNER TO ispuser;

--
-- Name: catalogo_tipos_orden; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_tipos_orden (
    codigo text NOT NULL,
    nombre text NOT NULL
);


ALTER TABLE public.catalogo_tipos_orden OWNER TO ispuser;

--
-- Name: catalogos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogos (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    descripcion text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.catalogos OWNER TO ispuser;

--
-- Name: catalogos_motivos_reagenda; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.catalogos_motivos_reagenda AS
 SELECT catalogo_motivos_reagenda.id,
    catalogo_motivos_reagenda.codigo,
    catalogo_motivos_reagenda.nombre,
    COALESCE(catalogo_motivos_reagenda.activo, true) AS activo,
    catalogo_motivos_reagenda.orden
   FROM public.catalogo_motivos_reagenda;


ALTER TABLE public.catalogos_motivos_reagenda OWNER TO ispuser;

--
-- Name: config_cargos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.config_cargos (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    recontratacion numeric DEFAULT '0'::numeric NOT NULL,
    instalacion numeric DEFAULT '0'::numeric NOT NULL,
    mensualidad numeric DEFAULT '0'::numeric NOT NULL,
    "cargoAdicional" numeric DEFAULT '0'::numeric NOT NULL,
    "creadoEn" timestamp without time zone DEFAULT now() NOT NULL,
    "actualizadoEn" timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.config_cargos OWNER TO ispuser;

--
-- Name: evidencias; Type: TABLE; Schema: public; Owner: ispuser
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


ALTER TABLE public.evidencias OWNER TO ispuser;

--
-- Name: inv_tecnico; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.inv_tecnico (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    tecnico_id uuid NOT NULL,
    material_id integer NOT NULL,
    cantidad numeric(14,3) DEFAULT '0'::numeric NOT NULL
);


ALTER TABLE public.inv_tecnico OWNER TO ispuser;

--
-- Name: materiales; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.materiales (
    id integer NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    precio numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    unidad_defecto text DEFAULT 'und'::text
);


ALTER TABLE public.materiales OWNER TO ispuser;

--
-- Name: materiales_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

CREATE SEQUENCE public.materiales_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.materiales_id_seq OWNER TO ispuser;

--
-- Name: materiales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ispuser
--

ALTER SEQUENCE public.materiales_id_seq OWNED BY public.materiales.id;


--
-- Name: municipios; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.municipios (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.municipios OWNER TO ispuser;

--
-- Name: orden_eventos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_eventos (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    orden_id uuid NOT NULL,
    tipo public.orden_evento_tipo NOT NULL,
    tecnico_id uuid,
    at timestamp with time zone DEFAULT now() NOT NULL,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    cierre_token text GENERATED ALWAYS AS ((payload ->> 'cierre_token'::text)) STORED
);


ALTER TABLE public.orden_eventos OWNER TO ispuser;

--
-- Name: vw_orden_eventos_resumen; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_orden_eventos_resumen AS
 SELECT orden_eventos.orden_id,
    min(orden_eventos.created_at) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'iniciar'::text)) AS primera_iniciada,
    max(orden_eventos.created_at) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'cerrar'::text)) AS ultima_cerrada,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'iniciar'::text)) AS cnt_inicios,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'cerrar'::text)) AS cnt_cierres
   FROM public.orden_eventos
  GROUP BY orden_eventos.orden_id;


ALTER TABLE public.vw_orden_eventos_resumen OWNER TO ispuser;

--
-- Name: vw_orden_sla; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_orden_sla AS
 SELECT r.orden_id,
    r.primera_iniciada,
    r.ultima_cerrada,
        CASE
            WHEN ((r.primera_iniciada IS NOT NULL) AND (r.ultima_cerrada IS NOT NULL)) THEN (EXTRACT(epoch FROM (r.ultima_cerrada - r.primera_iniciada)))::bigint
            ELSE NULL::bigint
        END AS duracion_seg
   FROM public.vw_orden_eventos_resumen r;


ALTER TABLE public.vw_orden_sla OWNER TO ispuser;

--
-- Name: mv_orden_sla; Type: MATERIALIZED VIEW; Schema: public; Owner: ispuser
--

CREATE MATERIALIZED VIEW public.mv_orden_sla AS
 SELECT vw_orden_sla.orden_id,
    vw_orden_sla.primera_iniciada,
    vw_orden_sla.ultima_cerrada,
    vw_orden_sla.duracion_seg
   FROM public.vw_orden_sla
  WITH NO DATA;


ALTER TABLE public.mv_orden_sla OWNER TO ispuser;

--
-- Name: orden_cierres_idem; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_cierres_idem (
    id integer NOT NULL,
    orden_codigo character varying(32) NOT NULL,
    payload_hash character varying(64) NOT NULL,
    idempotency_key character varying(128),
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    response_status integer,
    response_body jsonb
);


ALTER TABLE public.orden_cierres_idem OWNER TO ispuser;

--
-- Name: orden_cierres_idem_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

CREATE SEQUENCE public.orden_cierres_idem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.orden_cierres_idem_id_seq OWNER TO ispuser;

--
-- Name: orden_cierres_idem_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ispuser
--

ALTER SEQUENCE public.orden_cierres_idem_id_seq OWNED BY public.orden_cierres_idem.id;


--
-- Name: orden_evidencias; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_evidencias (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    orden_id uuid NOT NULL,
    tipo text NOT NULL,
    url text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.orden_evidencias OWNER TO ispuser;

--
-- Name: orden_materiales; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_materiales (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    orden_id uuid NOT NULL,
    precio_unitario numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    total_calculado numeric(14,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    material_id uuid DEFAULT gen_random_uuid() NOT NULL,
    cantidad integer DEFAULT 1 NOT NULL,
    descontado boolean DEFAULT false NOT NULL,
    material_id_int integer
);


ALTER TABLE public.orden_materiales OWNER TO ispuser;

--
-- Name: ordenes; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ordenes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text DEFAULT ((('INS-'::text || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'::text)) || '-'::text) || substr(md5((public.uuid_generate_v4())::text), 1, 4)) NOT NULL,
    estado text DEFAULT 'agendada'::text NOT NULL,
    tecnico_id uuid,
    iniciada_at timestamp with time zone,
    cerrada_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    firma_key text,
    pdf_url text,
    pdf_key text,
    subtotal numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    total numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    cierre_token uuid,
    tipo text,
    form_data jsonb,
    usuario_id uuid,
    agendado_para date,
    turno text,
    motivo_cancelacion text,
    cancelada_at timestamp with time zone,
    anulada_at timestamp with time zone,
    agendada_at timestamp with time zone,
    motivo_codigo text,
    motivo_reagenda_codigo text,
    motivo_reagenda text,
    CONSTRAINT chk_pdf_pair CHECK ((((pdf_key IS NULL) AND (pdf_url IS NULL)) OR ((pdf_key IS NOT NULL) AND (pdf_url IS NOT NULL))))
);


ALTER TABLE public.ordenes OWNER TO ispuser;

--
-- Name: planes; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.planes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo character varying NOT NULL,
    nombre character varying NOT NULL,
    vel_mbps integer NOT NULL,
    alta_costo numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mensual numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    tipo text DEFAULT 'internet'::text NOT NULL
);


ALTER TABLE public.planes OWNER TO ispuser;

--
-- Name: sectores; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.sectores (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    municipio_codigo text NOT NULL,
    zona text,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.sectores OWNER TO ispuser;

--
-- Name: smartolt_logs; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.smartolt_logs (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    endpoint text,
    request_payload jsonb,
    response_code integer,
    response_body jsonb,
    error text,
    request_id text
);


ALTER TABLE public.smartolt_logs OWNER TO ispuser;

--
-- Name: tecnicos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.tecnicos (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text NOT NULL,
    nombre text,
    telefono text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.tecnicos OWNER TO ispuser;

--
-- Name: typeorm_migrations; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.typeorm_migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.typeorm_migrations OWNER TO ispuser;

--
-- Name: typeorm_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

CREATE SEQUENCE public.typeorm_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.typeorm_migrations_id_seq OWNER TO ispuser;

--
-- Name: typeorm_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ispuser
--

ALTER SEQUENCE public.typeorm_migrations_id_seq OWNED BY public.typeorm_migrations.id;


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.usuarios (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo character varying(20) NOT NULL,
    tipo_cliente character varying NOT NULL,
    nombre character varying(120) NOT NULL,
    apellido character varying(120) NOT NULL,
    documento character varying(30) NOT NULL,
    email character varying,
    telefono character varying,
    estado public.usuario_estado DEFAULT 'nuevo'::public.usuario_estado NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    estado_conexion public.usuario_estado_conexion DEFAULT 'conectado'::public.usuario_estado_conexion
);


ALTER TABLE public.usuarios OWNER TO ispuser;

--
-- Name: ventas; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ventas (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo character varying(20) NOT NULL,
    cliente_nombre character varying(120) NOT NULL,
    cliente_apellido character varying(120) NOT NULL,
    documento character varying(30) NOT NULL,
    usuario_id uuid NOT NULL,
    estado character varying(20) DEFAULT 'creada'::character varying NOT NULL,
    plan_codigo character varying(20) NOT NULL,
    plan_nombre character varying(120) NOT NULL,
    plan_vel_mbps integer,
    alta_costo numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mensual_internet numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mensual_tv numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    mensual_total numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    incluye_tv boolean DEFAULT false NOT NULL,
    total numeric(12,2) DEFAULT '0'::numeric NOT NULL,
    recibo_pdf_key character varying,
    contrato_pdf_key character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.ventas OWNER TO ispuser;

--
-- Name: vias; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.vias (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.vias OWNER TO ispuser;

--
-- Name: vw_catalogo_motivos_reagenda_activos; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_catalogo_motivos_reagenda_activos AS
 SELECT catalogo_motivos_reagenda.id,
    catalogo_motivos_reagenda.codigo,
    catalogo_motivos_reagenda.nombre
   FROM public.catalogo_motivos_reagenda
  WHERE (catalogo_motivos_reagenda.activo = true);


ALTER TABLE public.vw_catalogo_motivos_reagenda_activos OWNER TO ispuser;

--
-- Name: vw_orden_eventos_detalle; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_orden_eventos_detalle AS
 SELECT e.id,
    e.orden_id,
    o.codigo,
    e.tecnico_id,
    (e.tipo)::text AS tipo,
    e.created_at,
    e.payload,
    o.estado AS estado_orden
   FROM (public.orden_eventos e
     LEFT JOIN public.ordenes o ON ((o.id = e.orden_id)));


ALTER TABLE public.vw_orden_eventos_detalle OWNER TO ispuser;

--
-- Name: vw_orden_eventos_hoy_por_tecnico; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_orden_eventos_hoy_por_tecnico AS
 SELECT orden_eventos.tecnico_id,
    date(orden_eventos.created_at) AS fecha,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'iniciar'::text)) AS inicios,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text ~~* 'cerrar'::text)) AS cierres
   FROM public.orden_eventos
  WHERE ((orden_eventos.created_at)::date = CURRENT_DATE)
  GROUP BY orden_eventos.tecnico_id, (date(orden_eventos.created_at));


ALTER TABLE public.vw_orden_eventos_hoy_por_tecnico OWNER TO ispuser;

--
-- Name: vw_orden_eventos_por_tecnico_fecha; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.vw_orden_eventos_por_tecnico_fecha AS
 SELECT orden_eventos.tecnico_id,
    date(orden_eventos.created_at) AS fecha,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text = 'iniciar'::text)) AS inicios,
    count(*) FILTER (WHERE ((orden_eventos.tipo)::text = 'cerrar'::text)) AS cierres
   FROM public.orden_eventos
  GROUP BY orden_eventos.tecnico_id, (date(orden_eventos.created_at));


ALTER TABLE public.vw_orden_eventos_por_tecnico_fecha OWNER TO ispuser;

--
-- Name: materiales id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales ALTER COLUMN id SET DEFAULT nextval('public.materiales_id_seq'::regclass);


--
-- Name: orden_cierres_idem id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_cierres_idem ALTER COLUMN id SET DEFAULT nextval('public.orden_cierres_idem_id_seq'::regclass);


--
-- Name: typeorm_migrations id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.typeorm_migrations ALTER COLUMN id SET DEFAULT nextval('public.typeorm_migrations_id_seq'::regclass);


--
-- Name: municipios PK_10d04b4b4e39ba40240b61e919d; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.municipios
    ADD CONSTRAINT "PK_10d04b4b4e39ba40240b61e919d" PRIMARY KEY (id);


--
-- Name: catalogos PK_1d78e1f35ded834637978e7cbf2; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogos
    ADD CONSTRAINT "PK_1d78e1f35ded834637978e7cbf2" PRIMARY KEY (id);


--
-- Name: smartolt_logs PK_391e78ee98bda31fd2a09c4411e; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.smartolt_logs
    ADD CONSTRAINT "PK_391e78ee98bda31fd2a09c4411e" PRIMARY KEY (id);


--
-- Name: vias PK_4d3096c822e57784a81ea79b71c; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.vias
    ADD CONSTRAINT "PK_4d3096c822e57784a81ea79b71c" PRIMARY KEY (id);


--
-- Name: tecnicos PK_57a82263172b130f3dafce11faa; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.tecnicos
    ADD CONSTRAINT "PK_57a82263172b130f3dafce11faa" PRIMARY KEY (id);


--
-- Name: ordenes PK_58713affeb8e3b7b30b9eeeee7a; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT "PK_58713affeb8e3b7b30b9eeeee7a" PRIMARY KEY (id);


--
-- Name: config_cargos PK_6bb3c3cc144d09d47a32b5bb491; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.config_cargos
    ADD CONSTRAINT "PK_6bb3c3cc144d09d47a32b5bb491" PRIMARY KEY (id);


--
-- Name: catalogo_items PK_8181cd85c9a0549622d3531bbc1; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_items
    ADD CONSTRAINT "PK_8181cd85c9a0549622d3531bbc1" PRIMARY KEY (id);


--
-- Name: orden_materiales PK_8fc75b2925fd0a02880631e033b; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_materiales
    ADD CONSTRAINT "PK_8fc75b2925fd0a02880631e033b" PRIMARY KEY (id);


--
-- Name: planes PK_91be19f449ba03767fe51acdebc; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT "PK_91be19f449ba03767fe51acdebc" PRIMARY KEY (id);


--
-- Name: app_users PK_9b97e4fbff9c2f3918fda27f999; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT "PK_9b97e4fbff9c2f3918fda27f999" PRIMARY KEY (id);


--
-- Name: ventas PK_b8b73abe8561829c019531d9a2e; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT "PK_b8b73abe8561829c019531d9a2e" PRIMARY KEY (id);


--
-- Name: typeorm_migrations PK_bb2f075707dd300ba86d0208923; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.typeorm_migrations
    ADD CONSTRAINT "PK_bb2f075707dd300ba86d0208923" PRIMARY KEY (id);


--
-- Name: materiales PK_bdb2febb21ca2abcdd52ec12559; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales
    ADD CONSTRAINT "PK_bdb2febb21ca2abcdd52ec12559" PRIMARY KEY (id);


--
-- Name: evidencias PK_c2e2ff397deaf434b623ed20507; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.evidencias
    ADD CONSTRAINT "PK_c2e2ff397deaf434b623ed20507" PRIMARY KEY (id);


--
-- Name: orden_cierres_idem PK_cac2a1d36659e270a31a42be423; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_cierres_idem
    ADD CONSTRAINT "PK_cac2a1d36659e270a31a42be423" PRIMARY KEY (id);


--
-- Name: usuarios PK_d7281c63c176e152e4c531594a8; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT "PK_d7281c63c176e152e4c531594a8" PRIMARY KEY (id);


--
-- Name: sectores PK_e4690b445beae51b850640e7d9d; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.sectores
    ADD CONSTRAINT "PK_e4690b445beae51b850640e7d9d" PRIMARY KEY (id);


--
-- Name: inv_tecnico PK_e58555e9ede4f85a4c9c5507bd0; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inv_tecnico
    ADD CONSTRAINT "PK_e58555e9ede4f85a4c9c5507bd0" PRIMARY KEY (id);


--
-- Name: materiales UQ_7fa98a683ce81de255c3bf2d26a; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales
    ADD CONSTRAINT "UQ_7fa98a683ce81de255c3bf2d26a" UNIQUE (nombre);


--
-- Name: catalogos UQ_8d2f3ffdd25acfdd036d9f9c89f; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogos
    ADD CONSTRAINT "UQ_8d2f3ffdd25acfdd036d9f9c89f" UNIQUE (codigo);


--
-- Name: tecnicos UQ_b41ede5014b9012fd7b2193b15e; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.tecnicos
    ADD CONSTRAINT "UQ_b41ede5014b9012fd7b2193b15e" UNIQUE (codigo);


--
-- Name: planes UQ_f255684b3d2b750ac6788c5ab98; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT "UQ_f255684b3d2b750ac6788c5ab98" UNIQUE (codigo);


--
-- Name: cargos cargos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_pkey PRIMARY KEY (id);


--
-- Name: catalogo_motivos_reagenda catalogo_motivos_reagenda_codigo_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_reagenda
    ADD CONSTRAINT catalogo_motivos_reagenda_codigo_key UNIQUE (codigo);


--
-- Name: catalogo_motivos_reagenda catalogo_motivos_reagenda_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_reagenda
    ADD CONSTRAINT catalogo_motivos_reagenda_pkey PRIMARY KEY (id);


--
-- Name: catalogo_tipos_orden catalogo_tipos_orden_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_tipos_orden
    ADD CONSTRAINT catalogo_tipos_orden_pkey PRIMARY KEY (codigo);


--
-- Name: orden_eventos orden_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_eventos
    ADD CONSTRAINT orden_eventos_pkey PRIMARY KEY (id);


--
-- Name: orden_evidencias orden_evidencias_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_evidencias
    ADD CONSTRAINT orden_evidencias_pkey PRIMARY KEY (id);


--
-- Name: IDX_11ee5476fd4f40aeac06660adf; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_11ee5476fd4f40aeac06660adf" ON public.ordenes USING btree (tecnico_id);


--
-- Name: IDX_12fab9892d22718370d6dccf6d; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX "IDX_12fab9892d22718370d6dccf6d" ON public.ordenes USING btree (codigo);


--
-- Name: IDX_2a6ea126337a50ff6015bfecc5; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_2a6ea126337a50ff6015bfecc5" ON public.vias USING btree (nombre);


--
-- Name: IDX_2c17841acc4939a08f19c52a57; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_2c17841acc4939a08f19c52a57" ON public.sectores USING btree (zona);


--
-- Name: IDX_5072fbd7a1300b1b92deb33a08; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX "IDX_5072fbd7a1300b1b92deb33a08" ON public.orden_cierres_idem USING btree (orden_codigo, payload_hash);


--
-- Name: IDX_5d67cc2e38c80255e768c2b76a; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX "IDX_5d67cc2e38c80255e768c2b76a" ON public.app_users USING btree (username);


--
-- Name: IDX_814583e3af729c9ac5da5e7b1f; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_814583e3af729c9ac5da5e7b1f" ON public.orden_cierres_idem USING btree (idempotency_key);


--
-- Name: IDX_8f19fb7422f45e7269944bc415; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_8f19fb7422f45e7269944bc415" ON public.orden_materiales USING btree (material_id);


--
-- Name: IDX_aa8405c6457229608b11ba1460; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_aa8405c6457229608b11ba1460" ON public.municipios USING btree (nombre);


--
-- Name: IDX_b2bd0b3fee63f625763c2e0dca; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX "IDX_b2bd0b3fee63f625763c2e0dca" ON public.catalogo_items USING btree (catalogo_id, codigo);


--
-- Name: IDX_ca61f54e17be66859316ac5d87; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_ca61f54e17be66859316ac5d87" ON public.municipios USING btree (codigo);


--
-- Name: IDX_d46fcb1f01d3037310b7594acb; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_d46fcb1f01d3037310b7594acb" ON public.sectores USING btree (nombre);


--
-- Name: IDX_d69a8b13b58fcfa4a03dcc738b; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_d69a8b13b58fcfa4a03dcc738b" ON public.vias USING btree (codigo);


--
-- Name: IDX_dd19774e0d20316832704b857f; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_dd19774e0d20316832704b857f" ON public.sectores USING btree (municipio_codigo);


--
-- Name: IDX_e66a559ea34d60d39bf0f16b6f; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_e66a559ea34d60d39bf0f16b6f" ON public.ordenes USING btree (estado);


--
-- Name: IDX_eca538e4af115ad2b8f0292573; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX "IDX_eca538e4af115ad2b8f0292573" ON public.orden_materiales USING btree (orden_id);


--
-- Name: idx_usuarios_estado; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_usuarios_estado ON public.usuarios USING btree (estado);


--
-- Name: ix_cargos_usuario; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_cargos_usuario ON public.cargos USING btree (usuario_id, aplicado);


--
-- Name: ix_catalogo_motivos_reagenda_orden; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_catalogo_motivos_reagenda_orden ON public.catalogo_motivos_reagenda USING btree (orden);


--
-- Name: ix_inv_tecnico_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_inv_tecnico_material ON public.inv_tecnico USING btree (material_id);


--
-- Name: ix_inv_tecnico_tecnico; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_inv_tecnico_tecnico ON public.inv_tecnico USING btree (tecnico_id);


--
-- Name: ix_mv_sla_fecha_bot; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mv_sla_fecha_bot ON public.mv_orden_sla USING btree ((((ultima_cerrada AT TIME ZONE 'America/Bogota'::text))::date));


--
-- Name: ix_mv_sla_fecha_utc_expr; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mv_sla_fecha_utc_expr ON public.mv_orden_sla USING btree ((((ultima_cerrada AT TIME ZONE 'UTC'::text))::date));


--
-- Name: ix_mv_sla_orden; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mv_sla_orden ON public.mv_orden_sla USING btree (orden_id);


--
-- Name: ix_mv_sla_ultima; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mv_sla_ultima ON public.mv_orden_sla USING btree (ultima_cerrada);


--
-- Name: ix_oe_orden; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_orden ON public.orden_evidencias USING btree (orden_id);


--
-- Name: ix_oe_orden_at_desc; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_orden_at_desc ON public.orden_eventos USING btree (orden_id, at DESC);


--
-- Name: ix_oe_orden_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_orden_created ON public.orden_eventos USING btree (orden_id, created_at DESC);


--
-- Name: ix_oe_tecnico_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_tecnico_created ON public.orden_eventos USING btree (tecnico_id, created_at DESC);


--
-- Name: ix_oe_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_tipo ON public.orden_eventos USING btree (tipo);


--
-- Name: ix_oe_tipo_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_tipo_created ON public.orden_eventos USING btree (tipo, created_at DESC);


--
-- Name: ix_om_pendientes; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_om_pendientes ON public.orden_materiales USING btree (orden_id) WHERE (descontado = false);


--
-- Name: ix_ordenes_agendado_para; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_agendado_para ON public.ordenes USING btree (agendado_para);


--
-- Name: ix_ordenes_id; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_id ON public.ordenes USING btree (id);


--
-- Name: ix_ordenes_turno; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_turno ON public.ordenes USING btree (turno);


--
-- Name: ix_ordenes_usuario; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_usuario ON public.ordenes USING btree (usuario_id);


--
-- Name: uq_mv_sla_orden; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX uq_mv_sla_orden ON public.mv_orden_sla USING btree (orden_id);


--
-- Name: uq_oe_cerrar_por_token; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX uq_oe_cerrar_por_token ON public.orden_eventos USING btree (orden_id, cierre_token);


--
-- Name: uq_oe_orden_tipo_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX uq_oe_orden_tipo_created ON public.orden_eventos USING btree (orden_id, tipo, created_at);


--
-- Name: uq_ordenes_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX uq_ordenes_codigo ON public.ordenes USING btree (codigo);


--
-- Name: ux_materiales_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_materiales_codigo ON public.materiales USING btree (codigo);


--
-- Name: ux_om_orden_mat_int; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_om_orden_mat_int ON public.orden_materiales USING btree (orden_id, material_id_int) WHERE (material_id_int IS NOT NULL);


--
-- Name: ux_orden_materiales_orden_mat; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_materiales_orden_mat ON public.orden_materiales USING btree (orden_id, material_id);


--
-- Name: inv_tecnico inv_tecnico_bi_merge; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER inv_tecnico_bi_merge BEFORE INSERT ON public.inv_tecnico FOR EACH ROW EXECUTE FUNCTION public.inv_tecnico_merge();


--
-- Name: orden_materiales om_biu_merge; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER om_biu_merge BEFORE INSERT OR UPDATE ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.om_material_id_merge();


--
-- Name: orden_materiales trg_om_material_id_default; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_om_material_id_default BEFORE INSERT OR UPDATE OF material_id ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.om_material_id_default();


--
-- Name: orden_materiales trg_om_material_id_merge; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_om_material_id_merge BEFORE INSERT OR UPDATE OF material_id ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.om_material_id_merge();


--
-- Name: ordenes trg_ordenes_log_eventos; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_ordenes_log_eventos AFTER UPDATE ON public.ordenes FOR EACH ROW EXECUTE FUNCTION public.fn_log_orden_eventos();


--
-- Name: usuarios trg_usuarios_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_usuarios_updated_at BEFORE UPDATE ON public.usuarios FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: inv_tecnico FK_bd07979d0f4a7392f0971ae8c25; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inv_tecnico
    ADD CONSTRAINT "FK_bd07979d0f4a7392f0971ae8c25" FOREIGN KEY (material_id) REFERENCES public.materiales(id) ON DELETE RESTRICT;


--
-- Name: inv_tecnico FK_c33ac7cde98755d25f0905c641e; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inv_tecnico
    ADD CONSTRAINT "FK_c33ac7cde98755d25f0905c641e" FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id) ON DELETE CASCADE;


--
-- Name: catalogo_items FK_c6775a06bda18c043cf5163791f; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_items
    ADD CONSTRAINT "FK_c6775a06bda18c043cf5163791f" FOREIGN KEY (catalogo_id) REFERENCES public.catalogos(id) ON DELETE CASCADE;


--
-- Name: orden_materiales FK_eca538e4af115ad2b8f02925731; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_materiales
    ADD CONSTRAINT "FK_eca538e4af115ad2b8f02925731" FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: cargos cargos_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: cargos cargos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: orden_evidencias fk_oe_orden; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_evidencias
    ADD CONSTRAINT fk_oe_orden FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: orden_materiales fk_om_material_int; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_materiales
    ADD CONSTRAINT fk_om_material_int FOREIGN KEY (material_id_int) REFERENCES public.materiales(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: ordenes fk_ordenes_usuario; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT fk_ordenes_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: orden_eventos orden_eventos_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_eventos
    ADD CONSTRAINT orden_eventos_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: orden_eventos orden_eventos_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_eventos
    ADD CONSTRAINT orden_eventos_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict j1njRIl1sgTX815j0JTSaY7AptLMQfZvGdOm81rEaP8TaYkLo6KWvyr6tTQVCya

