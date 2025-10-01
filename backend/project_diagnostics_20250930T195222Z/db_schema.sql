--
-- PostgreSQL database dump
--

\restrict O9gxEQd5jgDD1v95fisEt13Aie5m5zarGyYIVie0pvxSyoDYYGdcj1BGDIf51Kp

-- Dumped from database version 14.19
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
-- Name: public; Type: SCHEMA; Schema: -; Owner: ispuser
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO ispuser;

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
-- Name: orden_materiales_set_updated_at(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.orden_materiales_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.orden_materiales_set_updated_at() OWNER TO ispuser;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO ispuser;

--
-- Name: sync_stock_desde_kardex(uuid, integer); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.sync_stock_desde_kardex(p_almacen uuid, p_material_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_saldo int;
BEGIN
  SELECT COALESCE(SUM(delta), 0)
    INTO v_saldo
  FROM public.kardex
  WHERE almacen_id = p_almacen
    AND material_id = p_material_id;

  -- TODO: reemplazar tecnico_id=1 por join a tabla de mapeo almacen<->tecnico si aplica
  UPDATE public.inventario_tecnico_stock its
  SET stock = v_saldo
  WHERE its.material_id = p_material_id
    AND its.tecnico_id = 1;
END$$;


ALTER FUNCTION public.sync_stock_desde_kardex(p_almacen uuid, p_material_id integer) OWNER TO ispuser;

--
-- Name: trg_sync_stock_movimientos(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.trg_sync_stock_movimientos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  a_old uuid; a_new uuid;
  m_old int;  m_new int;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.almacen_origen_id  IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(NEW.almacen_origen_id,  NEW.material_id);
    END IF;
    IF NEW.almacen_destino_id IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(NEW.almacen_destino_id, NEW.material_id);
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    a_old := OLD.almacen_origen_id;  a_new := NEW.almacen_origen_id;
    m_old := OLD.material_id;        m_new := NEW.material_id;

    -- Origen (antes y después)
    IF a_old IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(a_old, COALESCE(m_old, NEW.material_id));
    END IF;
    IF a_new IS NOT NULL AND (a_new <> a_old OR m_new <> m_old) THEN
      PERFORM public.sync_stock_desde_kardex(a_new, m_new);
    END IF;

    -- Destino (antes y después)
    a_old := OLD.almacen_destino_id; a_new := NEW.almacen_destino_id;
    IF a_old IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(a_old, COALESCE(m_old, NEW.material_id));
    END IF;
    IF a_new IS NOT NULL AND (a_new <> a_old OR m_new <> m_old) THEN
      PERFORM public.sync_stock_desde_kardex(a_new, m_new);
    END IF;

  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.almacen_origen_id  IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(OLD.almacen_origen_id,  OLD.material_id);
    END IF;
    IF OLD.almacen_destino_id IS NOT NULL THEN
      PERFORM public.sync_stock_desde_kardex(OLD.almacen_destino_id, OLD.material_id);
    END IF;
  END IF;

  RETURN NULL; -- AFTER trigger: retorno no usado
END$$;


ALTER FUNCTION public.trg_sync_stock_movimientos() OWNER TO ispuser;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _almacen_uuid_map; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public._almacen_uuid_map (
    id_int integer NOT NULL,
    id_uuid uuid NOT NULL
);


ALTER TABLE public._almacen_uuid_map OWNER TO ispuser;

--
-- Name: almacenes; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.almacenes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    tecnico_id integer,
    CONSTRAINT almacenes_tipo_check CHECK ((tipo = ANY (ARRAY['principal'::text, 'tecnico'::text])))
);


ALTER TABLE public.almacenes OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_motivos_reagenda (
    id integer NOT NULL,
    codigo text,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.catalogo_motivos_reagenda OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

CREATE SEQUENCE public.catalogo_motivos_reagenda_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.catalogo_motivos_reagenda_id_seq OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ispuser
--

ALTER SEQUENCE public.catalogo_motivos_reagenda_id_seq OWNED BY public.catalogo_motivos_reagenda.id;


--
-- Name: idem_requests; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.idem_requests (
    key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.idem_requests OWNER TO ispuser;

--
-- Name: inv_tecnico; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.inv_tecnico (
    tecnico_id integer NOT NULL,
    material_id integer NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.inv_tecnico OWNER TO ispuser;

--
-- Name: inventario_movimientos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.inventario_movimientos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    tipo text NOT NULL,
    referencia text,
    material_id integer NOT NULL,
    cantidad integer NOT NULL,
    tecnico_id integer,
    nota text,
    user_id text,
    idem_key text
);


ALTER TABLE public.inventario_movimientos OWNER TO ispuser;

--
-- Name: inventario_tecnico_stock; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.inventario_tecnico_stock (
    tecnico_id integer NOT NULL,
    material_id integer NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL,
    stock integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.inventario_tecnico_stock OWNER TO ispuser;

--
-- Name: movimientos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.movimientos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    idempotency_key text,
    tipo text NOT NULL,
    almacen_origen_id uuid,
    almacen_destino_id uuid,
    material_id integer NOT NULL,
    cantidad integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    motivo text,
    ref_externa text,
    evidencia_key text,
    usuario_op_id integer,
    CONSTRAINT movimientos_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'ajuste'::text, 'transferencia'::text])))
);


ALTER TABLE public.movimientos OWNER TO ispuser;

--
-- Name: kardex; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.kardex AS
 SELECT m.id,
    m.tipo,
    m.almacen_origen_id,
    m.almacen_destino_id,
    COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
    m.material_id,
        CASE
            WHEN ((m.tipo = 'transferencia'::text) AND (m.almacen_destino_id IS NOT NULL)) THEN 'ingreso'::text
            WHEN ((m.tipo = 'transferencia'::text) AND (m.almacen_origen_id IS NOT NULL)) THEN 'egreso'::text
            ELSE m.tipo
        END AS etiqueta,
        CASE
            WHEN ((m.tipo = ANY (ARRAY['ingreso'::text, 'ajuste'::text])) AND (m.almacen_destino_id IS NOT NULL)) THEN m.cantidad
            WHEN ((m.tipo = 'egreso'::text) AND (m.almacen_origen_id IS NOT NULL)) THEN (- m.cantidad)
            WHEN ((m.tipo = 'transferencia'::text) AND (m.almacen_destino_id IS NOT NULL)) THEN m.cantidad
            WHEN ((m.tipo = 'transferencia'::text) AND (m.almacen_origen_id IS NOT NULL)) THEN (- m.cantidad)
            ELSE 0
        END AS delta,
    m.cantidad,
    m.created_at
   FROM public.movimientos m;


ALTER TABLE public.kardex OWNER TO ispuser;

--
-- Name: materiales; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.materiales (
    id integer NOT NULL,
    codigo text,
    nombre text NOT NULL,
    precio numeric(12,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.materiales OWNER TO ispuser;

--
-- Name: orden_evidencias; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_evidencias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    orden_id integer NOT NULL,
    tipo text NOT NULL,
    url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.orden_evidencias OWNER TO ispuser;

--
-- Name: orden_materiales; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_materiales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    material_id integer NOT NULL,
    cantidad integer DEFAULT 1 NOT NULL,
    descontado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    orden_id uuid NOT NULL
);


ALTER TABLE public.orden_materiales OWNER TO ispuser;

--
-- Name: ordenes; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ordenes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo text NOT NULL,
    tipo text DEFAULT 'INS'::text NOT NULL,
    estado text DEFAULT 'creada'::text NOT NULL,
    agendado_para date,
    turno text,
    agendada_at timestamp with time zone,
    iniciada_at timestamp with time zone,
    cerrada_at timestamp with time zone,
    cancelada_at timestamp with time zone,
    motivo_cancelacion text,
    usuario_id uuid,
    tecnico_id uuid
);


ALTER TABLE public.ordenes OWNER TO ispuser;

--
-- Name: stock_almacen; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.stock_almacen (
    almacen_id uuid NOT NULL,
    material_id integer NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.stock_almacen OWNER TO ispuser;

--
-- Name: tecnicos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.tecnicos (
    id integer NOT NULL,
    nombre text DEFAULT 'Técnico'::text NOT NULL
);


ALTER TABLE public.tecnicos OWNER TO ispuser;

--
-- Name: catalogo_motivos_reagenda id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_reagenda ALTER COLUMN id SET DEFAULT nextval('public.catalogo_motivos_reagenda_id_seq'::regclass);


--
-- Name: _almacen_uuid_map _almacen_uuid_map_id_uuid_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public._almacen_uuid_map
    ADD CONSTRAINT _almacen_uuid_map_id_uuid_key UNIQUE (id_uuid);


--
-- Name: _almacen_uuid_map _almacen_uuid_map_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public._almacen_uuid_map
    ADD CONSTRAINT _almacen_uuid_map_pkey PRIMARY KEY (id_int);


--
-- Name: almacenes almacenes_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT almacenes_pkey PRIMARY KEY (id);


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
-- Name: idem_requests idem_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.idem_requests
    ADD CONSTRAINT idem_requests_pkey PRIMARY KEY (key);


--
-- Name: inv_tecnico inv_tecnico_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inv_tecnico
    ADD CONSTRAINT inv_tecnico_pkey PRIMARY KEY (tecnico_id, material_id);


--
-- Name: inventario_movimientos inventario_movimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inventario_movimientos
    ADD CONSTRAINT inventario_movimientos_pkey PRIMARY KEY (id);


--
-- Name: inventario_tecnico_stock inventario_tecnico_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inventario_tecnico_stock
    ADD CONSTRAINT inventario_tecnico_stock_pkey PRIMARY KEY (tecnico_id, material_id);


--
-- Name: materiales materiales_codigo_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales
    ADD CONSTRAINT materiales_codigo_key UNIQUE (codigo);


--
-- Name: materiales materiales_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales
    ADD CONSTRAINT materiales_pkey PRIMARY KEY (id);


--
-- Name: movimientos movimientos_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.movimientos
    ADD CONSTRAINT movimientos_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: movimientos movimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.movimientos
    ADD CONSTRAINT movimientos_pkey PRIMARY KEY (id);


--
-- Name: orden_evidencias orden_evidencias_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_evidencias
    ADD CONSTRAINT orden_evidencias_pkey PRIMARY KEY (id);


--
-- Name: orden_materiales orden_materiales_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_materiales
    ADD CONSTRAINT orden_materiales_pkey PRIMARY KEY (id);


--
-- Name: ordenes ordenes_codigo_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_codigo_key UNIQUE (codigo);


--
-- Name: ordenes ordenes_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT ordenes_pkey PRIMARY KEY (id);


--
-- Name: stock_almacen stock_almacen_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.stock_almacen
    ADD CONSTRAINT stock_almacen_pkey PRIMARY KEY (almacen_id, material_id);


--
-- Name: tecnicos tecnicos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.tecnicos
    ADD CONSTRAINT tecnicos_pkey PRIMARY KEY (id);


--
-- Name: inventario_tecnico_stock uq_inv_tecnico_stock_tecnico_material; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inventario_tecnico_stock
    ADD CONSTRAINT uq_inv_tecnico_stock_tecnico_material UNIQUE (tecnico_id, material_id);


--
-- Name: orden_materiales uq_orden_materiales_orden_material; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_materiales
    ADD CONSTRAINT uq_orden_materiales_orden_material UNIQUE (orden_id, material_id);


--
-- Name: stock_almacen uq_stock_almacen_almacen_material; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.stock_almacen
    ADD CONSTRAINT uq_stock_almacen_almacen_material UNIQUE (almacen_id, material_id);


--
-- Name: idx_ordenes_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_codigo ON public.ordenes USING btree (codigo);


--
-- Name: ix_movs_dest_mat_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_movs_dest_mat_created ON public.movimientos USING btree (almacen_destino_id, material_id, created_at DESC);


--
-- Name: ix_movs_orig_mat_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_movs_orig_mat_created ON public.movimientos USING btree (almacen_origen_id, material_id, created_at DESC);


--
-- Name: kardex kardex_insert; Type: RULE; Schema: public; Owner: ispuser
--

CREATE RULE kardex_insert AS
    ON INSERT TO public.kardex DO INSTEAD  INSERT INTO public.movimientos (tipo, almacen_origen_id, almacen_destino_id, material_id, cantidad)
  VALUES (
        CASE
            WHEN (new.etiqueta = 'ingreso'::text) THEN 'ingreso'::text
            ELSE 'egreso'::text
        END,
        CASE
            WHEN (new.etiqueta = 'egreso'::text) THEN new.almacen_id
            ELSE NULL::uuid
        END,
        CASE
            WHEN (new.etiqueta = 'ingreso'::text) THEN new.almacen_id
            ELSE NULL::uuid
        END, new.material_id, GREATEST(abs(COALESCE(new.cantidad, new.delta, 0)), 0));


--
-- Name: movimientos trg_movs_sync_stock; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_movs_sync_stock AFTER INSERT OR DELETE OR UPDATE ON public.movimientos FOR EACH ROW EXECUTE FUNCTION public.trg_sync_stock_movimientos();


--
-- Name: orden_materiales trg_orden_materiales_set_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_orden_materiales_set_updated_at BEFORE UPDATE ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.orden_materiales_set_updated_at();


--
-- Name: orden_materiales trg_orden_materiales_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_orden_materiales_updated_at BEFORE UPDATE ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: almacenes almacenes_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT almacenes_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id);


--
-- Name: stock_almacen stock_almacen_almacen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.stock_almacen
    ADD CONSTRAINT stock_almacen_almacen_id_fkey FOREIGN KEY (almacen_id) REFERENCES public.almacenes(id) ON DELETE CASCADE;


--
-- Name: stock_almacen stock_almacen_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.stock_almacen
    ADD CONSTRAINT stock_almacen_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.materiales(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: ispuser
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict O9gxEQd5jgDD1v95fisEt13Aie5m5zarGyYIVie0pvxSyoDYYGdcj1BGDIf51Kp

