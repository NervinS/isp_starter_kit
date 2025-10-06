--
-- PostgreSQL database dump
--

\restrict Zk30U0UGCV5UimuYWMhj6DylfehIoLqTdEA5A8ZjVfPAH3kW2TRxtNHyOsVF2mA

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
-- Name: movimiento_tipo; Type: TYPE; Schema: public; Owner: ispuser
--

CREATE TYPE public.movimiento_tipo AS ENUM (
    'ingreso',
    'egreso',
    'ajuste',
    'transferencia'
);


ALTER TYPE public.movimiento_tipo OWNER TO ispuser;

--
-- Name: fn_mov_simple(text, uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_simple(_tipo text, _almacen uuid, _material integer, _cantidad numeric, _nota text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE _id uuid; _delta numeric;
BEGIN
  IF _tipo NOT IN ('ingreso','egreso','ajuste') THEN RAISE EXCEPTION 'Tipo inválido %', _tipo; END IF;
  IF _cantidad <= 0 THEN RAISE EXCEPTION 'Cantidad debe ser > 0'; END IF;

  _delta := CASE WHEN _tipo='egreso' THEN -_cantidad ELSE _cantidad END;
  PERFORM public.fn_stock_apply(_almacen, _material, _delta);

  INSERT INTO public.movimientos(
    tipo, material_id, cantidad,
    from_almacen_id, to_almacen_id, nota
  ) VALUES (
    _tipo, _material, _cantidad,
    CASE WHEN _tipo='egreso' THEN _almacen END,
    CASE WHEN _tipo IN ('ingreso','ajuste') THEN _almacen END,
    _nota
  ) RETURNING id INTO _id;

  RETURN _id;
END $$;


ALTER FUNCTION public.fn_mov_simple(_tipo text, _almacen uuid, _material integer, _cantidad numeric, _nota text) OWNER TO ispuser;

--
-- Name: fn_mov_simple_std(text, uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_simple_std(p_tipo text, p_almacen_id uuid, p_material_id integer, p_cantidad numeric, p_nota text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- 1) Intento preferido: (tipo text, material_id int, almacen_id uuid, cantidad numeric, nota text)
  BEGIN
    PERFORM public.fn_mov_simple(p_tipo, p_material_id::int, p_almacen_id, p_cantidad, p_nota);
    RETURN;
  EXCEPTION WHEN undefined_function THEN
    -- sigue al 2º intento
    NULL;
  END;

  -- 2) Alternativa: (tipo text, almacen_id uuid, material_id int, cantidad numeric, nota text)
  BEGIN
    PERFORM public.fn_mov_simple(p_tipo, p_almacen_id, p_material_id::int, p_cantidad, p_nota);
    RETURN;
  EXCEPTION WHEN undefined_function THEN
    RAISE EXCEPTION 'No existe ninguna variante soportada de fn_mov_simple (int-first ni uuid-first).';
  END;
END;
$$;


ALTER FUNCTION public.fn_mov_simple_std(p_tipo text, p_almacen_id uuid, p_material_id integer, p_cantidad numeric, p_nota text) OWNER TO ispuser;

--
-- Name: fn_mov_traslado(uuid, uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_traslado(_from uuid, _to uuid, _material integer, _cantidad numeric, _nota text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  _id uuid;
BEGIN
  -- Aplica stock en ambos almacenes
  PERFORM public.fn_stock_apply(_from, _material, -_cantidad);
  PERFORM public.fn_stock_apply(_to,   _material,  _cantidad);

  -- Inserta movimiento con columnas explícitas
  INSERT INTO public.movimientos (
    tipo, material_id, cantidad, fecha,
    from_almacen_id, to_almacen_id, nota
  )
  VALUES (
    'traslado', _material, _cantidad, now(),
    _from, _to, _nota
  )
  RETURNING id INTO _id;

  RETURN _id;
END;
$$;


ALTER FUNCTION public.fn_mov_traslado(_from uuid, _to uuid, _material integer, _cantidad numeric, _nota text) OWNER TO ispuser;

--
-- Name: fn_mov_traslado_std(uuid, uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_traslado_std(p_from_id uuid, p_to_id uuid, p_material_id integer, p_cantidad numeric, p_nota text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Intento 1: firma canónica (from, to, material, cantidad, nota) en ese orden
  BEGIN
    PERFORM public.fn_mov_traslado(p_from_id, p_to_id, p_material_id::int, p_cantidad, p_nota);
    RETURN;
  EXCEPTION WHEN undefined_function THEN
    -- Si tuvieras otra variante con orden invertido, puedes agregar más intentos aquí.
    RAISE EXCEPTION 'No existe ninguna variante soportada de fn_mov_traslado.';
  END;
END;
$$;


ALTER FUNCTION public.fn_mov_traslado_std(p_from_id uuid, p_to_id uuid, p_material_id integer, p_cantidad numeric, p_nota text) OWNER TO ispuser;

--
-- Name: fn_stock_apply(uuid, integer, numeric); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_stock_apply(_almacen uuid, _material integer, _delta numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  LOOP
    UPDATE public.stock_almacen
       SET cantidad   = GREATEST(0, cantidad + _delta),
           updated_at = now()
     WHERE almacen_id = _almacen
       AND material_id = _material;

    IF FOUND THEN
      RETURN;
    END IF;

    BEGIN
      INSERT INTO public.stock_almacen (almacen_id, material_id, cantidad, updated_at)
      VALUES (_almacen, _material, GREATEST(0, _delta), now());
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- otro proceso insertó en paralelo, reintentar
    END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.fn_stock_apply(_almacen uuid, _material integer, _delta numeric) OWNER TO ispuser;

--
-- Name: orden_equipos_set_updated_at(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.orden_equipos_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END;$$;


ALTER FUNCTION public.orden_equipos_set_updated_at() OWNER TO ispuser;

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
-- Name: ordenes_set_updated_at(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.ordenes_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      NEW.updated_at := now();
      RETURN NEW;
    END;
    $$;


ALTER FUNCTION public.ordenes_set_updated_at() OWNER TO ispuser;

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
    tipo text DEFAULT 'principal'::text NOT NULL,
    tecnico_id integer,
    codigo text NOT NULL,
    nombre text,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT almacenes_tipo_check CHECK ((tipo = ANY (ARRAY['principal'::text, 'tecnico'::text])))
);


ALTER TABLE public.almacenes OWNER TO ispuser;

--
-- Name: catalogo_equipos_material; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_equipos_material (
    equipo_tipo text NOT NULL,
    material_id integer NOT NULL,
    CONSTRAINT catalogo_equipos_material_equipo_tipo_check CHECK ((equipo_tipo = ANY (ARRAY['ONT'::text, 'REPEATER'::text])))
);


ALTER TABLE public.catalogo_equipos_material OWNER TO ispuser;

--
-- Name: catalogo_motivos_anulacion; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.catalogo_motivos_anulacion (
    id bigint NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.catalogo_motivos_anulacion OWNER TO ispuser;

--
-- Name: catalogo_motivos_anulacion_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

CREATE SEQUENCE public.catalogo_motivos_anulacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.catalogo_motivos_anulacion_id_seq OWNER TO ispuser;

--
-- Name: catalogo_motivos_anulacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: ispuser
--

ALTER SEQUENCE public.catalogo_motivos_anulacion_id_seq OWNED BY public.catalogo_motivos_anulacion.id;


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
-- Name: equipos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.equipos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo text NOT NULL,
    sn text,
    mac text,
    estandar text,
    estado text DEFAULT 'EN_STOCK'::text NOT NULL,
    owner_tipo text DEFAULT 'ALMACEN'::text NOT NULL,
    owner_id text,
    notas text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT equipos_estado_check CHECK ((estado = ANY (ARRAY['EN_STOCK'::text, 'ASIGNADO_TECNICO'::text, 'ASIGNADO_USUARIO'::text, 'RETIRADO'::text]))),
    CONSTRAINT equipos_estandar_check CHECK ((estandar = ANY (ARRAY['wifi4'::text, 'wifi5'::text, 'wifi6'::text, 'wifi7'::text]))),
    CONSTRAINT equipos_owner_tipo_check CHECK ((owner_tipo = ANY (ARRAY['ALMACEN'::text, 'TECNICO'::text, 'USUARIO'::text]))),
    CONSTRAINT equipos_tipo_check CHECK ((tipo = ANY (ARRAY['ONU'::text, 'REPETIDOR'::text])))
);


ALTER TABLE public.equipos OWNER TO ispuser;

--
-- Name: equipos_movs; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.equipos_movs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    equipo_id uuid NOT NULL,
    from_owner_tipo text,
    from_owner_id text,
    to_owner_tipo text,
    to_owner_id text,
    motivo text,
    orden_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT equipos_movs_from_owner_tipo_check CHECK ((from_owner_tipo = ANY (ARRAY['ALMACEN'::text, 'TECNICO'::text, 'USUARIO'::text]))),
    CONSTRAINT equipos_movs_to_owner_tipo_check CHECK ((to_owner_tipo = ANY (ARRAY['ALMACEN'::text, 'TECNICO'::text, 'USUARIO'::text])))
);


ALTER TABLE public.equipos_movs OWNER TO ispuser;

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
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    from_almacen_id uuid,
    to_almacen_id uuid,
    tecnico_id integer,
    nota text,
    CONSTRAINT movimientos_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'ajuste'::text, 'traslado'::text])))
);


ALTER TABLE public.movimientos OWNER TO ispuser;

--
-- Name: inventario_kardex_view; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.inventario_kardex_view AS
 SELECT m.id,
    m.fecha,
    m.material_id,
    m.tipo,
    m.from_almacen_id,
    m.to_almacen_id,
    m.cantidad,
    m.nota
   FROM public.movimientos m;


ALTER TABLE public.inventario_kardex_view OWNER TO ispuser;

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
-- Name: inventario_tecnico_traza; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.inventario_tecnico_traza (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    accion text NOT NULL,
    tecnico_id integer NOT NULL,
    material_id integer NOT NULL,
    cantidad numeric NOT NULL,
    from_almacen uuid,
    to_almacen uuid,
    nota text,
    CONSTRAINT inventario_tecnico_traza_accion_check CHECK ((accion = ANY (ARRAY['devolucion'::text, 'asignacion'::text]))),
    CONSTRAINT inventario_tecnico_traza_cantidad_check CHECK ((cantidad > (0)::numeric))
);


ALTER TABLE public.inventario_tecnico_traza OWNER TO ispuser;

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
    precio numeric(12,2) DEFAULT 0 NOT NULL,
    unidad text,
    activo boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.materiales OWNER TO ispuser;

--
-- Name: materiales_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

ALTER TABLE public.materiales ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.materiales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orden_equipos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.orden_equipos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    orden_id uuid NOT NULL,
    equipo_tipo text NOT NULL,
    serial text NOT NULL,
    accion text NOT NULL,
    aplicado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT orden_equipos_accion_check CHECK ((accion = ANY (ARRAY['asignar'::text, 'retirar'::text, 'mantener'::text]))),
    CONSTRAINT orden_equipos_equipo_tipo_check CHECK ((equipo_tipo = ANY (ARRAY['ONT'::text, 'REPEATER'::text])))
);


ALTER TABLE public.orden_equipos OWNER TO ispuser;

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
    tecnico_id uuid,
    venta_id uuid,
    motivo_anulacion text,
    motivo_anulacion_id integer,
    payload_abierto jsonb,
    payload_cierre jsonb,
    evidencias jsonb,
    pdf_url text,
    pdf_key text,
    firma_key text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_ordenes_tipo CHECK ((tipo = ANY (ARRAY['INS'::text, 'MAN'::text, 'COR'::text, 'REC'::text, 'BAJ'::text, 'TRA'::text, 'CMB'::text, 'RCT'::text]))),
    CONSTRAINT ck_orden_anulada_con_motivo CHECK (((estado <> 'anulada'::text) OR ((motivo_anulacion_id IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM motivo_cancelacion), ''::text) IS NOT NULL))))
);


ALTER TABLE public.ordenes OWNER TO ispuser;

--
-- Name: ordenes_datos_tecnicos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ordenes_datos_tecnicos (
    orden_id uuid NOT NULL,
    plan_codigo text,
    plan_nombre text,
    incluye_tv boolean,
    pon_sn text,
    onu_estandar text,
    repetidor_mac text,
    con_roseta boolean,
    marquilla text,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT ordenes_datos_tecnicos_onu_estandar_check CHECK ((onu_estandar = ANY (ARRAY['wifi4'::text, 'wifi5'::text, 'wifi6'::text, 'wifi7'::text])))
);


ALTER TABLE public.ordenes_datos_tecnicos OWNER TO ispuser;

--
-- Name: ordenes_evidencias; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ordenes_evidencias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    orden_id uuid NOT NULL,
    tipo text NOT NULL,
    obj_key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ordenes_evidencias_tipo_check CHECK ((tipo = ANY (ARRAY['foto'::text, 'firma'::text])))
);


ALTER TABLE public.ordenes_evidencias OWNER TO ispuser;

--
-- Name: ordenes_pdf; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ordenes_pdf (
    orden_id uuid NOT NULL,
    acta_pdf_key text,
    generado_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.ordenes_pdf OWNER TO ispuser;

--
-- Name: stock_almacen; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.stock_almacen (
    almacen_id uuid NOT NULL,
    material_id integer NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT ck_stock_no_negativo CHECK ((cantidad >= 0)),
    CONSTRAINT stock_almacen_cantidad_nonneg CHECK ((cantidad >= 0))
);


ALTER TABLE public.stock_almacen OWNER TO ispuser;

--
-- Name: tecnicos; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.tecnicos (
    id integer NOT NULL,
    nombre text DEFAULT 'Técnico'::text NOT NULL,
    codigo text,
    activo boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.tecnicos OWNER TO ispuser;

--
-- Name: tecnicos_id_seq; Type: SEQUENCE; Schema: public; Owner: ispuser
--

ALTER TABLE public.tecnicos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tecnicos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_codigo text NOT NULL,
    estado text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT usuarios_estado_check CHECK ((estado = ANY (ARRAY['creado'::text, 'instalado'::text, 'desconectado'::text, 'terminado'::text])))
);


ALTER TABLE public.usuarios OWNER TO ispuser;

--
-- Name: v_kardex; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.v_kardex AS
 SELECT m.id,
    m.fecha,
    m.tipo,
    m.material_id,
    m.cantidad,
    COALESCE(m.to_almacen_id, m.from_almacen_id) AS almacen_id,
        CASE
            WHEN ((m.tipo = ANY (ARRAY['ingreso'::text, 'devolucion'::text])) AND (m.to_almacen_id IS NOT NULL)) THEN m.cantidad
            WHEN (m.tipo = 'ajuste'::text) THEN m.cantidad
            WHEN ((m.tipo = 'egreso'::text) AND (m.from_almacen_id IS NOT NULL)) THEN (- m.cantidad)
            WHEN ((m.tipo = 'traslado'::text) AND (m.to_almacen_id IS NOT NULL)) THEN m.cantidad
            WHEN ((m.tipo = 'traslado'::text) AND (m.from_almacen_id IS NOT NULL)) THEN (- m.cantidad)
            ELSE 0
        END AS delta,
    m.from_almacen_id,
    m.to_almacen_id,
    m.tecnico_id,
    m.nota
   FROM public.movimientos m;


ALTER TABLE public.v_kardex OWNER TO ispuser;

--
-- Name: v_kardex_det; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.v_kardex_det AS
 SELECT mv.id,
    mv.fecha,
    mv.tipo,
    mv.material_id,
    m.codigo AS material_codigo,
    m.nombre AS material_nombre,
    COALESCE(mv.from_almacen_id, mv.to_almacen_id) AS almacen_id,
    a.codigo AS almacen_codigo,
    a.nombre AS almacen_nombre,
    mv.from_almacen_id,
    a_from.codigo AS from_almacen_codigo,
    mv.to_almacen_id,
    a_to.codigo AS to_almacen_codigo,
    mv.cantidad,
        CASE
            WHEN (mv.tipo = 'egreso'::text) THEN (- mv.cantidad)
            ELSE mv.cantidad
        END AS delta,
    mv.nota,
        CASE
            WHEN (a.tipo = 'tecnico'::text) THEN a.tecnico_id
            ELSE NULL::integer
        END AS tecnico_id
   FROM ((((public.movimientos mv
     LEFT JOIN public.materiales m ON ((m.id = mv.material_id)))
     LEFT JOIN public.almacenes a ON ((a.id = COALESCE(mv.from_almacen_id, mv.to_almacen_id))))
     LEFT JOIN public.almacenes a_from ON ((a_from.id = mv.from_almacen_id)))
     LEFT JOIN public.almacenes a_to ON ((a_to.id = mv.to_almacen_id)));


ALTER TABLE public.v_kardex_det OWNER TO ispuser;

--
-- Name: venta_pagos_idem; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.venta_pagos_idem (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    idem_key text NOT NULL,
    venta_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.venta_pagos_idem OWNER TO ispuser;

--
-- Name: ventas; Type: TABLE; Schema: public; Owner: ispuser
--

CREATE TABLE public.ventas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo character varying(20) NOT NULL,
    cliente_nombre character varying(120) NOT NULL,
    cliente_apellido character varying(120) NOT NULL,
    documento character varying(30) NOT NULL,
    usuario_id uuid DEFAULT gen_random_uuid() NOT NULL,
    estado character varying(20) DEFAULT 'creada'::character varying NOT NULL,
    plan character varying(120) NOT NULL,
    mensual_total numeric(12,2) DEFAULT 0 NOT NULL,
    total numeric(12,2) DEFAULT 0 NOT NULL,
    recibo_pdf_key text,
    contrato_pdf_key text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    cedula_img_key text,
    recibo_img_key text,
    firma_img_key text
);


ALTER TABLE public.ventas OWNER TO ispuser;

--
-- Name: ventas_firma_pendiente; Type: VIEW; Schema: public; Owner: ispuser
--

CREATE VIEW public.ventas_firma_pendiente AS
 SELECT ventas.codigo,
    ventas.estado,
    (ventas.firma_img_key IS NULL) AS requiere_firma
   FROM public.ventas;


ALTER TABLE public.ventas_firma_pendiente OWNER TO ispuser;

--
-- Name: catalogo_motivos_anulacion id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_anulacion ALTER COLUMN id SET DEFAULT nextval('public.catalogo_motivos_anulacion_id_seq'::regclass);


--
-- Name: catalogo_motivos_reagenda id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_reagenda ALTER COLUMN id SET DEFAULT nextval('public.catalogo_motivos_reagenda_id_seq'::regclass);


--
-- Name: typeorm_migrations id; Type: DEFAULT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.typeorm_migrations ALTER COLUMN id SET DEFAULT nextval('public.typeorm_migrations_id_seq'::regclass);


--
-- Name: typeorm_migrations PK_bb2f075707dd300ba86d0208923; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.typeorm_migrations
    ADD CONSTRAINT "PK_bb2f075707dd300ba86d0208923" PRIMARY KEY (id);


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
-- Name: catalogo_equipos_material catalogo_equipos_material_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_equipos_material
    ADD CONSTRAINT catalogo_equipos_material_pkey PRIMARY KEY (equipo_tipo);


--
-- Name: catalogo_motivos_anulacion catalogo_motivos_anulacion_nombre_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_anulacion
    ADD CONSTRAINT catalogo_motivos_anulacion_nombre_key UNIQUE (nombre);


--
-- Name: catalogo_motivos_anulacion catalogo_motivos_anulacion_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.catalogo_motivos_anulacion
    ADD CONSTRAINT catalogo_motivos_anulacion_pkey PRIMARY KEY (id);


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
-- Name: equipos equipos_mac_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos
    ADD CONSTRAINT equipos_mac_key UNIQUE (mac);


--
-- Name: equipos_movs equipos_movs_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos_movs
    ADD CONSTRAINT equipos_movs_pkey PRIMARY KEY (id);


--
-- Name: equipos equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos
    ADD CONSTRAINT equipos_pkey PRIMARY KEY (id);


--
-- Name: equipos equipos_sn_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos
    ADD CONSTRAINT equipos_sn_key UNIQUE (sn);


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
-- Name: inventario_tecnico_traza inventario_tecnico_traza_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inventario_tecnico_traza
    ADD CONSTRAINT inventario_tecnico_traza_pkey PRIMARY KEY (id);


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
-- Name: orden_equipos orden_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_equipos
    ADD CONSTRAINT orden_equipos_pkey PRIMARY KEY (id);


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
-- Name: ordenes_datos_tecnicos ordenes_datos_tecnicos_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_datos_tecnicos
    ADD CONSTRAINT ordenes_datos_tecnicos_pkey PRIMARY KEY (orden_id);


--
-- Name: ordenes_evidencias ordenes_evidencias_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_evidencias
    ADD CONSTRAINT ordenes_evidencias_pkey PRIMARY KEY (id);


--
-- Name: ordenes_pdf ordenes_pdf_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_pdf
    ADD CONSTRAINT ordenes_pdf_pkey PRIMARY KEY (orden_id);


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
-- Name: almacenes uq_almacenes_codigo; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT uq_almacenes_codigo UNIQUE (codigo);


--
-- Name: inventario_tecnico_stock uq_inv_tecnico_stock_tecnico_material; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.inventario_tecnico_stock
    ADD CONSTRAINT uq_inv_tecnico_stock_tecnico_material UNIQUE (tecnico_id, material_id);


--
-- Name: materiales uq_materiales_codigo; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.materiales
    ADD CONSTRAINT uq_materiales_codigo UNIQUE (codigo);


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
-- Name: tecnicos uq_tecnicos_codigo; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.tecnicos
    ADD CONSTRAINT uq_tecnicos_codigo UNIQUE (codigo);


--
-- Name: usuarios usuarios_cliente_codigo_key; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_cliente_codigo_key UNIQUE (cliente_codigo);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: orden_equipos ux_orden_equipo_serial_accion; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_equipos
    ADD CONSTRAINT ux_orden_equipo_serial_accion UNIQUE (orden_id, equipo_tipo, serial, accion);


--
-- Name: venta_pagos_idem venta_pagos_idem_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.venta_pagos_idem
    ADD CONSTRAINT venta_pagos_idem_pkey PRIMARY KEY (id);


--
-- Name: ventas ventas_pkey; Type: CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_pkey PRIMARY KEY (id);


--
-- Name: idx_movimientos_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movimientos_created ON public.movimientos USING btree (created_at);


--
-- Name: idx_movimientos_destino; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movimientos_destino ON public.movimientos USING btree (almacen_destino_id);


--
-- Name: idx_movimientos_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movimientos_material ON public.movimientos USING btree (material_id);


--
-- Name: idx_movimientos_origen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movimientos_origen ON public.movimientos USING btree (almacen_origen_id);


--
-- Name: idx_movs_destino; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movs_destino ON public.movimientos USING btree (almacen_destino_id) WHERE (almacen_destino_id IS NOT NULL);


--
-- Name: idx_movs_origen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movs_origen ON public.movimientos USING btree (almacen_origen_id) WHERE (almacen_origen_id IS NOT NULL);


--
-- Name: idx_movs_tipo_mat_fecha; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_movs_tipo_mat_fecha ON public.movimientos USING btree (tipo, material_id, fecha DESC);


--
-- Name: idx_ordenes_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_codigo ON public.ordenes USING btree (codigo);


--
-- Name: idx_ordenes_motivo_anulacion_id; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_motivo_anulacion_id ON public.ordenes USING btree (motivo_anulacion_id);


--
-- Name: idx_ordenes_tecnico_estado; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_tecnico_estado ON public.ordenes USING btree (tecnico_id, estado);


--
-- Name: idx_ordenes_tipo_estado; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_tipo_estado ON public.ordenes USING btree (tipo, estado);


--
-- Name: idx_ordenes_venta_id_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_ordenes_venta_id_tipo ON public.ordenes USING btree (venta_id, tipo);


--
-- Name: idx_stock_almacen_mat; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_stock_almacen_mat ON public.stock_almacen USING btree (almacen_id, material_id);


--
-- Name: idx_stock_almacen_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_stock_almacen_material ON public.stock_almacen USING btree (material_id);


--
-- Name: idx_stock_almacen_updated; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_stock_almacen_updated ON public.stock_almacen USING btree (updated_at);


--
-- Name: idx_traza_fecha; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_traza_fecha ON public.inventario_tecnico_traza USING btree (fecha DESC);


--
-- Name: idx_traza_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_traza_material ON public.inventario_tecnico_traza USING btree (material_id);


--
-- Name: idx_traza_tecnico; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_traza_tecnico ON public.inventario_tecnico_traza USING btree (tecnico_id);


--
-- Name: ix_cat_eq_mat_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_cat_eq_mat_material ON public.catalogo_equipos_material USING btree (material_id);


--
-- Name: ix_eqm_equipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_eqm_equipo ON public.equipos_movs USING btree (equipo_id);


--
-- Name: ix_eqm_to; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_eqm_to ON public.equipos_movs USING btree (to_owner_tipo, to_owner_id);


--
-- Name: ix_equipo_owner; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_equipo_owner ON public.equipos USING btree (owner_tipo, owner_id);


--
-- Name: ix_equipo_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_equipo_tipo ON public.equipos USING btree (tipo);


--
-- Name: ix_mov_fecha; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mov_fecha ON public.movimientos USING btree (fecha DESC);


--
-- Name: ix_mov_from_almacen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mov_from_almacen ON public.movimientos USING btree (from_almacen_id);


--
-- Name: ix_mov_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mov_material ON public.movimientos USING btree (material_id);


--
-- Name: ix_mov_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mov_tipo ON public.movimientos USING btree (tipo);


--
-- Name: ix_mov_to_almacen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_mov_to_almacen ON public.movimientos USING btree (to_almacen_id);


--
-- Name: ix_movs_dest_mat_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_movs_dest_mat_created ON public.movimientos USING btree (almacen_destino_id, material_id, created_at DESC);


--
-- Name: ix_movs_orig_mat_created; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_movs_orig_mat_created ON public.movimientos USING btree (almacen_origen_id, material_id, created_at DESC);


--
-- Name: ix_odt_onu_estandar; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_odt_onu_estandar ON public.ordenes_datos_tecnicos USING btree (onu_estandar);


--
-- Name: ix_oe_orden_id; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_orden_id ON public.ordenes_evidencias USING btree (orden_id);


--
-- Name: ix_oe_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_oe_tipo ON public.ordenes_evidencias USING btree (tipo);


--
-- Name: ix_orden_equipos_orden; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_orden_equipos_orden ON public.orden_equipos USING btree (orden_id);


--
-- Name: ix_ordenes_created_at; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_created_at ON public.ordenes USING btree (created_at);


--
-- Name: ix_ordenes_estado; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_estado ON public.ordenes USING btree (estado);


--
-- Name: ix_ordenes_motivo_anulacion; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_motivo_anulacion ON public.ordenes USING btree (estado) WHERE (motivo_anulacion IS NOT NULL);


--
-- Name: ix_ordenes_tecnico; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_tecnico ON public.ordenes USING btree (tecnico_id);


--
-- Name: ix_ordenes_tipo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_tipo ON public.ordenes USING btree (tipo);


--
-- Name: ix_ordenes_updated_at; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_updated_at ON public.ordenes USING btree (updated_at);


--
-- Name: ix_ordenes_usuario; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_usuario ON public.ordenes USING btree (usuario_id);


--
-- Name: ix_stock_almacen_almacen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_stock_almacen_almacen ON public.stock_almacen USING btree (almacen_id);


--
-- Name: ix_stock_almacen_mat; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_stock_almacen_mat ON public.stock_almacen USING btree (material_id);


--
-- Name: ix_usuarios_estado; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_usuarios_estado ON public.usuarios USING btree (estado);


--
-- Name: ix_venta_pagos_idem_venta; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_venta_pagos_idem_venta ON public.venta_pagos_idem USING btree (venta_id, created_at DESC);


--
-- Name: ux_orden_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_codigo ON public.ordenes USING btree (codigo);


--
-- Name: ux_orden_unica_ins_venta_activa; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_unica_ins_venta_activa ON public.ordenes USING btree (venta_id) WHERE ((tipo = 'INS'::text) AND (estado = ANY (ARRAY['creada'::text, 'agendada'::text, 'en_proceso'::text])));


--
-- Name: ux_stock_almacen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_stock_almacen ON public.stock_almacen USING btree (almacen_id, material_id);


--
-- Name: ux_venta_pagos_idem_key; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_venta_pagos_idem_key ON public.venta_pagos_idem USING btree (idem_key);


--
-- Name: ux_ventas_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_ventas_codigo ON public.ventas USING btree (codigo);


--
-- Name: orden_equipos trg_orden_equipos_set_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_orden_equipos_set_updated_at BEFORE UPDATE ON public.orden_equipos FOR EACH ROW EXECUTE FUNCTION public.orden_equipos_set_updated_at();


--
-- Name: orden_materiales trg_orden_materiales_set_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_orden_materiales_set_updated_at BEFORE UPDATE ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.orden_materiales_set_updated_at();


--
-- Name: orden_materiales trg_orden_materiales_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_orden_materiales_updated_at BEFORE UPDATE ON public.orden_materiales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: ordenes trg_ordenes_set_updated_at; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_ordenes_set_updated_at BEFORE UPDATE ON public.ordenes FOR EACH ROW EXECUTE FUNCTION public.ordenes_set_updated_at();


--
-- Name: almacenes almacenes_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT almacenes_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id);


--
-- Name: equipos_movs equipos_movs_equipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos_movs
    ADD CONSTRAINT equipos_movs_equipo_id_fkey FOREIGN KEY (equipo_id) REFERENCES public.equipos(id) ON DELETE CASCADE;


--
-- Name: equipos_movs equipos_movs_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.equipos_movs
    ADD CONSTRAINT equipos_movs_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE SET NULL;


--
-- Name: ordenes fk_ordenes_motivo_anulacion; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT fk_ordenes_motivo_anulacion FOREIGN KEY (motivo_anulacion_id) REFERENCES public.catalogo_motivos_anulacion(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: ordenes fk_ordenes_usuarios; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT fk_ordenes_usuarios FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: ordenes fk_ordenes_venta; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes
    ADD CONSTRAINT fk_ordenes_venta FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: movimientos movimientos_from_almacen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.movimientos
    ADD CONSTRAINT movimientos_from_almacen_id_fkey FOREIGN KEY (from_almacen_id) REFERENCES public.almacenes(id) ON DELETE SET NULL;


--
-- Name: movimientos movimientos_tecnico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.movimientos
    ADD CONSTRAINT movimientos_tecnico_id_fkey FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id) ON DELETE SET NULL;


--
-- Name: movimientos movimientos_to_almacen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.movimientos
    ADD CONSTRAINT movimientos_to_almacen_id_fkey FOREIGN KEY (to_almacen_id) REFERENCES public.almacenes(id) ON DELETE SET NULL;


--
-- Name: orden_equipos orden_equipos_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.orden_equipos
    ADD CONSTRAINT orden_equipos_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: ordenes_datos_tecnicos ordenes_datos_tecnicos_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_datos_tecnicos
    ADD CONSTRAINT ordenes_datos_tecnicos_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: ordenes_evidencias ordenes_evidencias_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_evidencias
    ADD CONSTRAINT ordenes_evidencias_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


--
-- Name: ordenes_pdf ordenes_pdf_orden_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: ispuser
--

ALTER TABLE ONLY public.ordenes_pdf
    ADD CONSTRAINT ordenes_pdf_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES public.ordenes(id) ON DELETE CASCADE;


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
-- PostgreSQL database dump complete
--

\unrestrict Zk30U0UGCV5UimuYWMhj6DylfehIoLqTdEA5A8ZjVfPAH3kW2TRxtNHyOsVF2mA

