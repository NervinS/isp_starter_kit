--
-- PostgreSQL database dump
--

\restrict uefRVQ8K5VMGPFAe4s3tMpU2N4b6sZCHZ02S5hL0D0lMhWwj4hT0B9BmpyIetC7

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
-- Name: fn_mov_simple(text, integer, uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_simple(tipo text, material_id integer, almacen_id uuid, cantidad numeric, nota text) RETURNS void
    LANGUAGE sql
    AS $$
      SELECT fn_mov_simple(tipo, almacen_id, material_id, cantidad, nota)
    $$;


ALTER FUNCTION public.fn_mov_simple(tipo text, material_id integer, almacen_id uuid, cantidad numeric, nota text) OWNER TO ispuser;

--
-- Name: fn_mov_simple(text, uuid, integer, numeric, text); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_mov_simple(_tipo text, _almacen uuid, _material integer, _cantidad numeric, _nota text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  _id    uuid;
  _delta numeric;
BEGIN
  IF _tipo NOT IN ('ingreso','egreso','ajuste') THEN
    RAISE EXCEPTION 'Tipo inválido %', _tipo;
  END IF;
  IF _cantidad <= 0 THEN
    RAISE EXCEPTION 'Cantidad debe ser > 0';
  END IF;

  _delta := CASE WHEN _tipo='egreso' THEN -_cantidad ELSE _cantidad END;

  -- Aplica stock
  PERFORM public.fn_stock_apply(_almacen, _material, _delta);

  -- Inserta y devuelve UUID
  INSERT INTO public.movimientos(
    tipo, material_id, cantidad,
    from_almacen_id, to_almacen_id, nota
  )
  VALUES (
    _tipo, _material, _cantidad,
    CASE WHEN _tipo='egreso' THEN _almacen END,
    CASE WHEN _tipo IN ('ingreso','ajuste') THEN _almacen END,
    _nota
  )
  RETURNING id INTO _id;

  RETURN _id;
END
$$;


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
-- Name: fn_movimientos_guardrail_saldo(); Type: FUNCTION; Schema: public; Owner: ispuser
--

CREATE FUNCTION public.fn_movimientos_guardrail_saldo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _from uuid;
  _needed integer;
  _have integer;
BEGIN
  IF NEW.tipo IN ('egreso','transferencia') THEN
    _needed := NEW.cantidad;
    _from   := NEW.almacen_origen_id;

    IF _from IS NOT NULL THEN
      SELECT COALESCE(cantidad,0) INTO _have
      FROM public.stock_almacen
      WHERE almacen_id = _from AND material_id = NEW.material_id
      FOR UPDATE; -- bloquea fila para evitar carrera

      IF _have < _needed THEN
        RAISE EXCEPTION 'Saldo insuficiente en almacén % para material %, requerido %, actual %',
          _from, NEW.material_id, _needed, _have
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_movimientos_guardrail_saldo() OWNER TO ispuser;

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
-- Data for Name: _almacen_uuid_map; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public._almacen_uuid_map (id_int, id_uuid) FROM stdin;
\.


--
-- Data for Name: almacenes; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.almacenes (id, tipo, tecnico_id, codigo, nombre, activo, created_at) FROM stdin;
a1f107e4-2184-4d88-aa04-39d31aa0c02d	principal	\N	PRINCIPAL	Almacén Principal	t	2025-10-01 22:37:20.78092+00
def98ffe-4f8b-401a-a9bc-afbdfa106cef	tecnico	10	TEC-10	Almacén Técnico Técnico 10	t	2025-10-01 22:37:20.78092+00
ffed73ac-5d98-439c-9bbb-165c83cd2c90	tecnico	8	TEC-8	Almacén Técnico Técnico 8	t	2025-10-01 22:37:20.78092+00
bdf0d98a-f0ee-4f42-a761-11be1a352e61	tecnico	6	TEC-6	Almacén Técnico Técnico 6	t	2025-10-01 22:37:20.78092+00
846d87aa-891c-4ed0-a9bb-a71594ec6654	tecnico	7	TEC-7	Almacén Técnico Técnico 7	t	2025-10-01 22:37:20.78092+00
4bc0b05d-1975-458e-a376-2806ab9183d1	tecnico	2	TEC-2	Almacén Técnico Técnico 2	t	2025-10-01 22:37:20.78092+00
cf5aa6c0-399d-4a4b-85bf-723afbb010d3	tecnico	5	TEC-5	Almacén Técnico Técnico 5	t	2025-10-01 22:37:20.78092+00
f4ed9ee3-b1ae-483a-aaf7-19840de8844a	tecnico	4	TEC-4	Almacén Técnico Técnico 4	t	2025-10-01 22:37:20.78092+00
beb7a8f6-28a2-4ad2-b121-5619580ba82d	tecnico	1	TEC-1	Almacén Técnico Técnico 1	t	2025-10-01 22:37:20.78092+00
c7be87bd-5f58-460f-bfe9-1baeda4853ad	tecnico	3	TEC-3	Almacén Técnico Técnico 3	t	2025-10-01 22:37:20.78092+00
c4b52045-75e4-4df6-b53b-6311fcebde37	tecnico	9	TEC-9	Almacén Técnico Técnico 9	t	2025-10-01 22:37:20.78092+00
bb09f0b8-69cd-4b34-9f66-1d58b0877671	principal	\N	ALM-bb09f0b8	Almacén	t	2025-10-01 22:37:20.78092+00
\.


--
-- Data for Name: catalogo_motivos_anulacion; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.catalogo_motivos_anulacion (id, nombre, activo, created_at) FROM stdin;
1	Doble registro	t	2025-10-01 17:03:43.825042+00
2	Error en los datos	t	2025-10-01 17:03:43.825042+00
3	Orden duplicada	t	2025-10-01 17:03:43.825042+00
4	Solicitud del cliente	t	2025-10-01 17:03:43.825042+00
5	No hay cobertura final	t	2025-10-01 17:10:22.924795+00
\.


--
-- Data for Name: catalogo_motivos_reagenda; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.catalogo_motivos_reagenda (id, codigo, nombre, activo, created_at) FROM stdin;
1	cliente-ausente	Cliente no disponible	t	2025-09-29 23:14:45.459168+00
2	cliente-no-disponible	Cliente reprograma	t	2025-09-29 23:14:45.459168+00
3	cliente-no-estaba	Cliente no estaba	t	2025-09-29 23:14:45.459168+00
4	direccion-incorrecta	Dirección incorrecta	t	2025-09-29 23:14:45.459168+00
5	clima	Condiciones climáticas	t	2025-09-29 23:14:45.459168+00
6	falla-tecnica	Falla técnica	t	2025-09-29 23:14:45.459168+00
7	otro	Otro	t	2025-09-29 23:14:45.459168+00
\.


--
-- Data for Name: equipos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.equipos (id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: equipos_movs; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.equipos_movs (id, equipo_id, from_owner_tipo, from_owner_id, to_owner_tipo, to_owner_id, motivo, orden_id, created_at) FROM stdin;
\.


--
-- Data for Name: idem_requests; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.idem_requests (key, created_at) FROM stdin;
close:MAN-250929192117:d6b5915c46057bcb005f46f6433df65609dd3a7a57af75ac1a5a4a7c299ebffb	2025-09-30 12:54:24.164761+00
close:MAN-250930130817:d6b5915c46057bcb005f46f6433df65609dd3a7a57af75ac1a5a4a7c299ebffb	2025-09-30 13:08:18.118163+00
\.


--
-- Data for Name: inv_tecnico; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.inv_tecnico (tecnico_id, material_id, cantidad) FROM stdin;
1	1	0
6	3	10
\.


--
-- Data for Name: inventario_movimientos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.inventario_movimientos (id, fecha, tipo, referencia, material_id, cantidad, tecnico_id, nota, user_id, idem_key) FROM stdin;
7f92f087-9fec-4f30-a98c-7f734cda7d0d	2025-09-30 20:51:15.399774+00	ingreso	tecnico:6	3	1	6	\N	\N	35363c0e-dba8-498c-8d52-0dd055fd6905
6103c01c-c6e0-427b-8f83-d6a252879049	2025-09-30 20:51:15.519212+00	egreso	tecnico:6	3	-1	6	\N	\N	521e64f8-34df-4e1f-8fa4-ea74512e987f
9533d9c0-dbe0-494c-8f1b-2b6d29dd9e5e	2025-09-30 21:00:02.254716+00	egreso	tecnico:6	3	-1	6	smoke egreso -1	\N	62b48209-c3b3-4601-b1ec-7e34bc12a583
8146d8ef-b796-4afb-9671-39dde4b18e4e	2025-09-30 21:00:17.498898+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	7984dbd8-17d3-42da-810e-404750ef4d8b
27db088e-c2e8-4456-bac9-fcfb658f004e	2025-09-30 21:07:56.581677+00	egreso	tecnico:6	3	-1	6	smoke egreso -1	\N	0c33b13c-9471-4c8d-badf-4118ab4a21a6
5680c2cf-b228-4c6a-a2ff-8ba34f8eab24	2025-09-30 21:15:44.929049+00	egreso	tecnico:6	3	-1	6	smoke egreso -1	\N	dd52014c-f413-4359-8015-a6c61e4e5572
cc676624-2cc0-4076-a938-6e63b2f0f0aa	2025-09-30 21:15:45.119135+00	egreso	tecnico:6	3	-999	6	\N	\N	smoke-1759266945
958edd14-eaad-4729-a550-39870e700b75	2025-09-30 21:22:15.163465+00	ingreso	tecnico:6	3	1	6	\N	\N	54150b22-5998-4d58-acd1-fb31265a28ca
47814eed-5981-447c-9f7e-15256c57bf1d	2025-09-30 21:22:15.28402+00	egreso	tecnico:6	3	-1	6	\N	\N	a4d58608-8a7c-4309-8bfc-206e9776f4a9
49ab24f6-184c-49e1-9707-efb610a830ec	2025-09-30 21:22:16.570177+00	egreso	tecnico:6	3	-1	6	smoke egreso -1	\N	45e08eed-2a3b-48e3-a030-7666b99f6a57
b24c2c63-38de-4e6a-b430-8551adbb69d4	2025-09-30 21:22:16.769914+00	egreso	tecnico:6	3	-999	6	\N	\N	smoke-1759267336
80571622-d9a1-4c30-896e-7e6c86038674	2025-09-30 21:23:22.388122+00	egreso	tecnico:6	3	-999	6	\N	\N	test-409-1759267402
497ceee6-eb78-4ac3-9f7b-7b1b01b27b25	2025-09-30 21:37:41.034018+00	ingreso	tecnico:6	3	1	6	\N	\N	ec1386b3-c025-4803-bfc1-b579c38139fd
3976b2f9-e7b1-48a1-96f2-aa84147b5312	2025-09-30 21:37:41.144675+00	egreso	tecnico:6	3	-1	6	\N	\N	5fb492ca-05f2-487d-8820-585522f6a989
f3217cdb-a8f7-42fc-bd3b-461a32b0ab9d	2025-09-30 21:37:42.21908+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	3d3bd2fe-daa1-4452-9573-dc80ca52aa52
32173cd4-b624-4f50-9df5-d072349983be	2025-09-30 21:37:42.647377+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759268262588
4f25ab49-393f-44d7-84dd-ba05c5b9a3e6	2025-09-30 21:41:02.929928+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	b8086f69-6f37-4976-9399-4da312cd5896
277dbd31-5f64-4999-a55d-95f5cc293634	2025-09-30 21:41:03.359073+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759268463300
8b29a317-b295-427e-8898-a31b865e743b	2025-09-30 21:43:46.939359+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	a8bd4b31-ab9e-49b8-a885-45cbfd45df65
14bf8401-2a9e-4b32-a115-3f56643233cb	2025-09-30 21:46:47.206211+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759268807129
fcd9b7e1-f6a6-4181-93fb-b9307349ee8d	2025-09-30 21:48:28.227182+00	ingreso	tecnico:6	3	1	6	\N	\N	ef52c8ce-7c74-4665-b645-03c845eb7c8a
1d2c893e-7d4b-43ed-9046-3471caf1f394	2025-09-30 21:48:28.338169+00	egreso	tecnico:6	3	-1	6	\N	\N	9ea843af-dc69-4c14-b086-f6ad0648bbf7
eebf9463-b528-4a4f-b8d1-5fca1fa7342f	2025-09-30 21:48:29.510961+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	585c33c1-75a4-443d-bde7-4411d9ef09ec
db21aa4e-656f-4473-9e01-bd9706e042bb	2025-09-30 21:48:29.951755+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759268909888
00bd9272-eb8f-4f58-9581-52a03377d253	2025-10-01 13:19:57.455321+00	ingreso	tecnico:6	3	1	6	setup +1 para prueba	\N	31b5095e-2c83-44af-8324-46b9c731aaf2
4cc22055-86e0-4085-9cd4-3abc75f4c678	2025-10-01 13:19:57.517327+00	egreso	tecnico:6	3	-1	6	\N	\N	check-ok-1759324797503
533c6fc7-2d9f-4b5f-8ab3-f4e98408311d	2025-10-01 14:04:59.76549+00	ingreso	tecnico:6	3	1	6	\N	\N	0eba114d-0902-4dd7-bf14-79767bbd78ab
9eb868b4-5cef-4e57-bc00-25df93226759	2025-10-01 14:04:59.882335+00	egreso	tecnico:6	3	-1	6	\N	\N	dca7fa8c-b0f1-45b6-a083-465b29597e38
c47980fc-e5f5-4dbb-be3e-872bda3f2474	2025-10-01 14:05:01.37449+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	af0446e1-28b6-4dc6-9fe9-e535758ba125
350322bb-c2df-45dc-bff7-df0f9efd4519	2025-10-01 14:05:01.825806+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759327501754
a3937455-efcf-4ba1-bf39-76f80213a2aa	2025-10-01 15:49:32.118721+00	ingreso	tecnico:6	3	1	6	\N	\N	c5973198-eb43-432c-8f96-b0f29dac4924
aa53ab05-75bb-42e7-a141-f1167a8a2777	2025-10-01 15:49:32.288618+00	egreso	tecnico:6	3	-1	6	\N	\N	38b7026d-6edc-4642-a4fd-ea1819dff551
1e13ce1a-9c36-402d-a632-4da9de2a2069	2025-10-01 15:49:33.629177+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	5d5766d3-45c7-4477-bdd8-0fc7e549ed27
dc493ae0-aa1a-43bd-84df-4d81ee1ca0e2	2025-10-01 15:49:34.072142+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759333774005
0fbe5dd2-089f-4930-9574-081d7d7a1e5e	2025-10-01 18:02:42.009412+00	ingreso	tecnico:6	3	1	6	\N	\N	fcf44030-b02b-4788-a40e-594854b57e38
d5de9c07-5023-4142-a737-6569447fd5b1	2025-10-01 18:02:42.122852+00	egreso	tecnico:6	3	-1	6	\N	\N	d045b391-454a-4b50-a546-b99e7970e843
d1a49c1c-6d24-4263-8887-e536bc87e1c2	2025-10-01 18:02:43.506769+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	1173a797-4367-4f50-8a93-51196fde80e9
fed2d8a2-9b5e-417a-8393-a630df7ee3de	2025-10-01 18:02:43.943344+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759341763881
4346d903-fabe-414f-b78b-fb82c53e1966	2025-10-01 18:21:31.908535+00	ingreso	tecnico:6	3	1	6	\N	\N	6fc080d4-6f6f-4d95-b95f-5de0affb7dce
aa940cf6-d607-4a28-9aa7-523548870dd6	2025-10-01 18:21:32.034769+00	egreso	tecnico:6	3	-1	6	\N	\N	2c4f19a5-715d-4b81-a1cc-3eb91374d132
25689573-70d7-4726-93be-5d27312f8e7b	2025-10-01 18:21:33.460742+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	2f793fd2-9d3c-4c56-9339-115f5e268bec
5a044d79-86d6-4eba-99c4-82cce840ec8e	2025-10-01 18:21:33.902564+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759342893837
902bf2d9-e25c-4d5a-8b47-2ab150caba72	2025-10-01 23:29:33.818755+00	ingreso	tecnico:6	3	1	6	\N	\N	0e8ef1b0-1acc-4f71-aa10-8a4092e7f759
ca75c27e-1fe7-4296-b3da-bf4670eb12b5	2025-10-01 23:29:33.937927+00	egreso	tecnico:6	3	-1	6	\N	\N	aba38dcf-a22a-4ef9-bd91-f56014e5f6ee
b02cac49-47c0-4c19-a927-ce3f8e9d55fa	2025-10-02 00:18:04.092496+00	ingreso	tecnico:6	3	1	6	\N	\N	5aef10ad-920e-4633-b2e8-1f4bbfd05924
c379500d-9aa2-4c3e-bba0-268abfa045f0	2025-10-02 00:18:04.206081+00	egreso	tecnico:6	3	-1	6	\N	\N	82980add-6eb3-4282-84cf-aa921c506250
f5536ae6-39eb-467d-b5f0-5229972cb7d4	2025-10-02 00:18:05.419994+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	86fdb1df-03e5-4c4b-aaf7-52b1d855dff6
eef6eaea-cfb2-4997-a9a8-e88f8114e8a6	2025-10-02 00:18:05.862743+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759364285796
a68d1e61-c3c4-42af-b380-348e8e8e1d00	2025-10-02 00:21:36.447041+00	ingreso	tecnico:6	3	1	6	\N	\N	b2af87b2-89ff-4a22-9b65-768dc42206fd
a397ce8b-dad8-4371-89cb-f337450a9599	2025-10-02 00:21:36.566376+00	egreso	tecnico:6	3	-1	6	\N	\N	2e894eab-78f3-4ec7-8030-0bb575c92d5d
49622237-a9b9-48b2-a28a-f127b60d95e6	2025-10-02 00:21:37.739121+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	21c27751-e326-4462-aae2-4d4287d817ae
f1a75030-87e9-47ba-a307-8ebcae55b7e8	2025-10-02 00:21:38.175539+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759364498112
68bd0652-4990-4145-b486-07da143b7c9f	2025-10-02 00:40:30.263531+00	ingreso	tecnico:6	3	1	6	\N	\N	e053804b-ac0f-4e6d-916e-4870f0e206a2
53a9315b-a428-4da1-9614-db66f70eb4f5	2025-10-02 00:40:30.38156+00	egreso	tecnico:6	3	-1	6	\N	\N	63b5326a-8dfb-49ec-a487-93b29af2ddd2
ce0412c6-81ac-452e-86f2-14ddb6f9452f	2025-10-02 00:40:31.569242+00	ingreso	tecnico:6	3	1	6	smoke ingreso +1	\N	e5e29281-323f-48f2-8111-9a73e4d65121
33dd8fc8-06c2-4876-9acb-e924d961d100	2025-10-02 00:40:32.011324+00	egreso	tecnico:6	3	-1	6	\N	\N	smoke-ok-1759365631945
\.


--
-- Data for Name: inventario_tecnico_stock; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.inventario_tecnico_stock (tecnico_id, material_id, cantidad, stock) FROM stdin;
1	3	2	67
6	3	0	0
1	1	999	-15
\.


--
-- Data for Name: materiales; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.materiales (id, codigo, nombre, precio, unidad, activo, created_at, updated_at) FROM stdin;
1	MAT-1	Material 1	1000.00	\N	t	2025-10-01 22:56:25.975012+00	2025-10-01 22:56:25.977093+00
2	MAT-2	Material 2	2000.00	\N	t	2025-10-01 22:56:25.975012+00	2025-10-01 22:56:25.977093+00
3	MAT-3	Material 3	3000.00	\N	t	2025-10-01 22:56:25.975012+00	2025-10-01 22:56:25.977093+00
4	MAT-RJ45	Conector RJ45	0.00	UND	t	2025-10-01 22:58:26.951357+00	2025-10-01 22:58:26.951357+00
\.


--
-- Data for Name: movimientos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.movimientos (id, idempotency_key, tipo, almacen_origen_id, almacen_destino_id, material_id, cantidad, created_at, motivo, ref_externa, evidencia_key, usuario_op_id, fecha, from_almacen_id, to_almacen_id, tecnico_id, nota) FROM stdin;
881ca8be-9acb-43ca-9a45-ea8411311bed	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-29 23:34:51.229735+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
e74e5c97-eca7-41cf-9688-dc4fc9b84fb8	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-29 23:34:51.229735+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
7866507e-ee62-4d87-a2f7-9562bb11e11e	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	1	5	2025-09-30 00:40:18.466512+00	carga inicial manual	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
0fc307eb-c4f5-482a-aaa8-d58eee99fde6	\N	ingreso	\N	beb7a8f6-28a2-4ad2-b121-5619580ba82d	1	5	2025-09-30 00:43:32.09624+00	carga inicial	seed-tecnico-1	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
04fee375-1441-415d-8e04-ac9d82e6c886	\N	ingreso	\N	beb7a8f6-28a2-4ad2-b121-5619580ba82d	1	2	2025-09-30 12:33:34.218039+00	seed extra	seed-tecnico-1-extra	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
3ef7858b-eca1-4272-853f-07ba6a826cab	auto-1759235621805-0.2048412563621278	ingreso	\N	beb7a8f6-28a2-4ad2-b121-5619580ba82d	1	1	2025-09-30 12:33:41.801083+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
151ccde9-4296-4568-a662-72d074ebd72c	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 13:04:38.897301+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
58b330b8-9b9b-4710-8543-fb2007df5fa7	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	2	2025-09-30 13:08:11.209689+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
fd7d1266-be61-4597-bce6-1cc63959419c	\N	egreso	\N	\N	1	1	2025-09-30 13:08:18.118163+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
4e9be4e2-0a2f-45eb-8713-96b8d43f474a	auto-1759237848521-0.48645480853323897	ingreso	\N	beb7a8f6-28a2-4ad2-b121-5619580ba82d	1	1	2025-09-30 13:10:48.516899+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
0c0d4878-dfb1-4c2c-bfd1-9efc87236dd8	1759238080984192532	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 13:14:41.055989+00	ajuste prueba	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
813ba685-ab05-49eb-b2e0-942ac897b248	1759238577204254734	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 13:22:57.290782+00	prueba trigger	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
9194a66f-b215-4e7a-8ae6-02615c0c1068	1759240250503377138	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 13:50:50.579917+00	prueba post-trigger	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
75398ab6-2cfd-4d51-af30-d067400c472d	auto-1759245985366-0.045769007555630736	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 15:26:25.361697+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
dec2d104-3311-4254-90ac-c436741dbb5b	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 15:26:38.733132+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
9b1e60c9-8d8e-43c1-9b53-d98970d2fdd6	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 15:26:38.733132+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
bd1208ea-ea4f-4fba-b242-4272b4f7b695	1759246228195271657	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 15:30:28.250596+00	smoke	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
26f3f679-530b-4040-80de-5e07571709a6	auto-1759249611001-0.0027756055534706725	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 16:26:50.9971+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
745ee944-c9a8-4099-bd7b-14ef810a5223	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 16:26:51.888891+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
e36c81bb-b93e-4719-85fd-74426222b33b	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 16:26:51.888891+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
ff07074a-5330-4a9c-b973-29d7500f1a8e	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 16:32:39.221392+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
b4721f10-5d46-4276-ae00-3280308e0448	auto-1759250331498-0.04644978088303664	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 16:38:51.493904+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
38ffd27b-973c-44b4-9e87-83db9748162a	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 16:38:52.324676+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
4a82232c-21b8-4a74-9457-78687ef67b67	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 16:38:52.324676+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
0abe6a56-35de-44e5-adba-e7f6f7acbfdf	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 16:38:53.85993+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
ff38e79c-fa6f-45f3-8678-37886400dcef	auto-1759251622347-0.676742869630772	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 17:00:22.343064+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
1dcc47f5-8738-4016-8b5f-67773fb0097c	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 17:00:23.204529+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
d29ba48c-3f81-4e68-bbff-853c3b2e5e22	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 17:00:23.204529+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
6f4dcebc-ee74-4529-a11d-b6b378333560	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 17:00:24.589213+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
c6d79fdf-8766-49c0-b956-20637c1a75f0	auto-1759252055125-0.48386905948725945	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 17:07:35.120775+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
c790f353-5a19-4b6c-a7b5-5691eefbc08b	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 17:07:35.992261+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
32befa77-2ca7-43e4-9847-bf529bb89101	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 17:07:35.992261+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
63d4c8df-bc6f-4c52-9407-9619f9d12b04	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 17:07:37.720783+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
4a9d9f8a-7a02-4fa9-94e9-81eece57db9c	auto-1759262753067-0.13653223739796072	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:05:53.060311+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
43773822-7a9d-4c54-8946-b40ec86536ba	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 20:05:53.937629+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
7399ada7-c906-48c5-a24e-778af3102fc7	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:05:53.937629+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
e4d22d1b-dbd5-4a8b-9786-c576e6781045	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 20:05:55.398264+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
83dbf68e-b9a8-46c3-8e49-3a9a927bbf34	auto-1759263681991-0.045727210724717304	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:21:21.9865+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
ea7d3b94-c337-42d8-84cb-30498fcbd339	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 20:21:22.823685+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
013647d4-3bc3-4b86-975f-62a52bf7366f	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:21:22.823685+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
788b8274-916c-426f-b426-56a2293ef595	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 20:21:24.320833+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
d06c61a8-5a73-4564-aad1-288e386cd071	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 20:48:13.592593+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
2e28b7f0-f6ad-4a31-8313-fda34f331d6a	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:48:13.592593+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
835826cb-9072-41a5-a2bf-7c70684782ff	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 20:48:14.869581+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
6e980995-f1ff-4b1a-a576-3cfff1dea802	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 20:51:16.085689+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
cb91d388-9c5d-4d58-8506-1f7ef96ecf1b	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 20:51:16.085689+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
a0dab3fe-366c-44d3-806b-c0222f17f87d	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 20:51:17.49492+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
a5901eb5-9617-4393-ad9f-69f27ba16b8f	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 21:22:15.844876+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
e594fbd6-ab09-453f-993b-ff135af76f44	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 21:22:15.844876+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
fcaeda97-9723-422d-94e2-b7fcbde0f390	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 21:37:41.680023+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
3dc18d97-a819-47e8-b822-a3ba3c0afd1d	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 21:37:41.680023+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
255f891b-9670-414a-bfb1-3f20f23d8088	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 21:37:43.992913+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
dcc2ea17-5b04-44fa-a400-ecc21ccb8d67	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-09-30 21:48:28.965712+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
1932ecab-9525-463d-8ff0-509ebadd8cf1	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-09-30 21:48:28.965712+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
440081e0-fc2a-4b37-a8fc-29c9291d82ed	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-09-30 21:48:31.3994+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
5a49576b-00b8-4f69-873c-5608627f72a7	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-01 14:05:00.51492+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
c71d7ebc-4eea-4675-9e33-8446ff53bb13	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-01 14:05:00.51492+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
e7aa8e88-9c6a-423f-bf35-cae3792e9286	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-01 14:05:03.321861+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
32eeb74a-8792-4b27-89db-44df4a0104ba	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-01 15:49:32.874066+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
95b852dd-f05f-4140-ae9f-528bcd9729d8	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-01 15:49:32.874066+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
9f54db04-02d8-421f-a626-b24f412a8333	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-01 15:49:35.810151+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
cb69f1ce-b8c6-430f-b83b-8c6b4e0210c4	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-01 18:02:42.750907+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
09989332-df21-441c-912f-811963edbc04	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-01 18:02:42.750907+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
aa65a293-f107-4a31-acb7-4946ac0b6624	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-01 18:02:45.893594+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
76cc7151-ab2e-4c7c-b7f2-007cc0833880	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-01 18:21:32.656028+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
2d141005-4d11-4c63-a309-d82fa1c15d85	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-01 18:21:32.656028+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
0a9aef33-0474-4825-b71b-a7f4556d46f2	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-01 18:21:35.954549+00	\N	\N	\N	\N	2025-10-01 23:27:56.107409+00	\N	\N	\N	\N
5801ce3a-bdd1-488b-a70d-b837911f6408	\N	traslado	\N	\N	3	1	2025-10-02 00:01:46.553693+00	\N	\N	\N	\N	2025-10-02 00:01:46.553693+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	traslado a tecnico 6
90aeb277-6527-48f6-ae00-b3ebbdffba2a	\N	traslado	\N	\N	3	1	2025-10-02 00:01:46.56459+00	\N	\N	\N	\N	2025-10-02 00:01:46.56459+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	devolucion tecnico 6
e5038394-6ddd-49fd-9ce8-cc36c234a80e	\N	traslado	\N	\N	3	1	2025-10-02 00:03:56.636637+00	\N	\N	\N	\N	2025-10-02 00:03:56.636637+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke traslado
c89899a7-357e-4e66-b4f6-aa8aa98ee030	\N	traslado	\N	\N	3	1	2025-10-02 00:03:56.648163+00	\N	\N	\N	\N	2025-10-02 00:03:56.648163+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke devolución
a3a3a22c-ca3d-44b2-928b-b3c23469472e	\N	traslado	\N	\N	3	1	2025-10-02 00:16:42.579095+00	\N	\N	\N	\N	2025-10-02 00:16:42.579095+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke auto traslado
e170b3c7-0394-4da2-b922-550dcf0e1b7b	\N	traslado	\N	\N	3	1	2025-10-02 00:16:42.65515+00	\N	\N	\N	\N	2025-10-02 00:16:42.65515+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke auto devolución
ff01885e-fe32-4504-844b-01cba5b35062	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-02 00:18:04.790728+00	\N	\N	\N	\N	2025-10-02 00:18:04.790728+00	\N	\N	\N	\N
24b15607-0803-44dc-a758-2c66994ac617	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-02 00:18:04.790728+00	\N	\N	\N	\N	2025-10-02 00:18:04.790728+00	\N	\N	\N	\N
ef470c84-b8f9-425f-803f-19403136390b	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-02 00:18:09.486299+00	\N	\N	\N	\N	2025-10-02 00:18:09.486299+00	\N	\N	\N	\N
5d1099e0-1e76-4eef-93f1-1d19ad575e1d	\N	traslado	\N	\N	3	1	2025-10-02 00:18:39.651418+00	\N	\N	\N	\N	2025-10-02 00:18:39.651418+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke auto traslado
93a1b995-ebe9-4543-b8f6-7f0a54001870	\N	traslado	\N	\N	3	1	2025-10-02 00:18:39.723595+00	\N	\N	\N	\N	2025-10-02 00:18:39.723595+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke auto devolución
197dff04-d467-435e-87f5-5a895f2f59a6	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-02 00:21:37.180064+00	\N	\N	\N	\N	2025-10-02 00:21:37.180064+00	\N	\N	\N	\N
6fb94b31-421f-4e6f-aae1-6409da4a4374	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-02 00:21:37.180064+00	\N	\N	\N	\N	2025-10-02 00:21:37.180064+00	\N	\N	\N	\N
21704a81-62ab-4e23-a32b-76a0f6ded8c8	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-02 00:21:41.79747+00	\N	\N	\N	\N	2025-10-02 00:21:41.79747+00	\N	\N	\N	\N
436a4fd1-3a02-475d-bd30-6cb83bed5bed	\N	traslado	\N	\N	3	1	2025-10-02 00:21:43.716873+00	\N	\N	\N	\N	2025-10-02 00:21:43.716873+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke auto traslado
97d3cd19-8049-415b-b7f3-3b6d1ced00f4	\N	traslado	\N	\N	3	1	2025-10-02 00:21:43.791241+00	\N	\N	\N	\N	2025-10-02 00:21:43.791241+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke auto devolución
db50100e-bfa6-4178-85e0-fc1c7f0152d1	\N	traslado	\N	\N	3	1	2025-10-02 00:32:01.548029+00	\N	\N	\N	\N	2025-10-02 00:32:01.548029+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke auto traslado
d68cd006-0b47-4e37-8dbf-7cfa7a95dd8c	\N	traslado	\N	\N	3	1	2025-10-02 00:32:01.624927+00	\N	\N	\N	\N	2025-10-02 00:32:01.624927+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke auto devolución
0ddb366a-46eb-4c3e-bf18-3ed47cef2040	\N	ingreso	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	2	2025-10-02 00:40:31.001953+00	\N	\N	\N	\N	2025-10-02 00:40:31.001953+00	\N	\N	\N	\N
43fd9a67-7aa1-42be-ad58-2524084f5e7b	\N	ajuste	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	1	2025-10-02 00:40:31.001953+00	\N	\N	\N	\N	2025-10-02 00:40:31.001953+00	\N	\N	\N	\N
54b2fc93-d98d-4a0a-8242-f9dfcdea3ce3	\N	egreso	beb7a8f6-28a2-4ad2-b121-5619580ba82d	\N	1	1	2025-10-02 00:40:35.625968+00	\N	\N	\N	\N	2025-10-02 00:40:35.625968+00	\N	\N	\N	\N
5b2c51df-4e34-42d8-9031-9385ba750613	\N	traslado	\N	\N	3	1	2025-10-02 00:40:37.301049+00	\N	\N	\N	\N	2025-10-02 00:40:37.301049+00	a1f107e4-2184-4d88-aa04-39d31aa0c02d	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke auto traslado
ecac8c1b-951e-4658-ab90-4b236c1cf27c	\N	traslado	\N	\N	3	1	2025-10-02 00:40:37.372347+00	\N	\N	\N	\N	2025-10-02 00:40:37.372347+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	a1f107e4-2184-4d88-aa04-39d31aa0c02d	\N	smoke auto devolución
ff1c89f1-2021-4847-86f2-0f06007b4f78	\N	ingreso	\N	\N	1	5	2025-10-02 16:48:21.412162+00	\N	\N	\N	\N	2025-10-02 16:48:21.412162+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	probe
33d3cdae-a668-4119-b7b1-9ced1504725e	\N	egreso	\N	\N	1	3	2025-10-02 16:48:21.629585+00	\N	\N	\N	\N	2025-10-02 16:48:21.629585+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	probe
f35b5b1a-55fb-4c68-9fca-8d26ea1bc398	\N	ajuste	\N	\N	1	2	2025-10-02 16:48:21.845033+00	\N	\N	\N	\N	2025-10-02 16:48:21.845033+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	set=2
dacca179-a3ab-45a0-bf95-77d158ab4dee	\N	ingreso	\N	\N	1	5	2025-10-02 16:48:30.829553+00	\N	\N	\N	\N	2025-10-02 16:48:30.829553+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	test ingreso
22f14a80-27cf-4812-8b02-48b78fa8208f	\N	egreso	\N	\N	1	3	2025-10-02 16:48:30.864338+00	\N	\N	\N	\N	2025-10-02 16:48:30.864338+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	test egreso
8e647307-8017-4eea-854a-92dba636a03f	\N	egreso	\N	\N	1	4	2025-10-02 16:48:30.908347+00	\N	\N	\N	\N	2025-10-02 16:48:30.908347+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] ajuste set 2
e91cc71f-e26c-4afb-bfb9-d456b9516249	\N	ingreso	\N	\N	1	5	2025-10-02 16:50:28.040464+00	\N	\N	\N	\N	2025-10-02 16:50:28.040464+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	test
2d63de59-c953-467b-b512-35969b274a82	\N	egreso	\N	\N	1	3	2025-10-02 16:50:28.047519+00	\N	\N	\N	\N	2025-10-02 16:50:28.047519+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	test
93a5e6b9-a456-4002-a1b0-c3dc1f5d7af8	\N	ajuste	\N	\N	1	2	2025-10-02 16:50:28.049612+00	\N	\N	\N	\N	2025-10-02 16:50:28.049612+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	set 2
095c5d82-7b16-43ad-98a3-f15fdc398099	\N	ingreso	\N	\N	1	5	2025-10-02 16:58:06.292607+00	\N	\N	\N	\N	2025-10-02 16:58:06.292607+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	test ingreso
da726592-0a0a-4aec-917e-e79bad2fe963	\N	egreso	\N	\N	1	3	2025-10-02 16:58:06.340587+00	\N	\N	\N	\N	2025-10-02 16:58:06.340587+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	test egreso
80ef69e3-4e28-4630-a859-0ccd1df167bc	\N	egreso	\N	\N	1	6	2025-10-02 16:58:06.381501+00	\N	\N	\N	\N	2025-10-02 16:58:06.381501+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] ajuste set 2
bd2735dd-e3f2-45ac-a6bf-6f15ed472159	\N	ingreso	\N	\N	1	5	2025-10-02 17:01:40.141944+00	\N	\N	\N	\N	2025-10-02 17:01:40.141944+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	test ingreso
fb704706-edb4-4db6-a6ad-187b037fa7e9	\N	egreso	\N	\N	1	3	2025-10-02 17:01:40.173822+00	\N	\N	\N	\N	2025-10-02 17:01:40.173822+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	test egreso
7deabbf1-891d-4df2-aaea-6c402d692e83	\N	egreso	\N	\N	1	2	2025-10-02 17:01:40.217145+00	\N	\N	\N	\N	2025-10-02 17:01:40.217145+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] ajuste set 2
3104b539-7923-4d36-8575-2f691d636b8d	\N	ingreso	\N	\N	1	5	2025-10-02 17:37:33.44858+00	\N	\N	\N	\N	2025-10-02 17:37:33.44858+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	e2e ingreso
459d43ff-01b2-4d26-87cb-e80be6a05d0f	\N	egreso	\N	\N	1	3	2025-10-02 17:37:33.474942+00	\N	\N	\N	\N	2025-10-02 17:37:33.474942+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	e2e egreso
4e7f8927-52a2-4722-8630-0c9e26452e3c	\N	egreso	\N	\N	1	2	2025-10-02 17:37:33.490346+00	\N	\N	\N	\N	2025-10-02 17:37:33.490346+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] e2e set=2
9231d3f6-900a-4bd7-8346-38beb36bc8c2	\N	ingreso	\N	\N	1	5	2025-10-02 17:39:50.797887+00	\N	\N	\N	\N	2025-10-02 17:39:50.797887+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	e2e ingreso
f2eeb38d-2b6d-41ed-8d31-ce0df4e3f57f	\N	egreso	\N	\N	1	3	2025-10-02 17:39:50.82694+00	\N	\N	\N	\N	2025-10-02 17:39:50.82694+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	e2e egreso
40d6421d-c3ea-48f9-a755-03cad8f3bafa	\N	egreso	\N	\N	1	2	2025-10-02 17:39:50.845873+00	\N	\N	\N	\N	2025-10-02 17:39:50.845873+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] e2e set=2
2993375e-cb46-4263-902e-237a01bea7da	\N	ingreso	\N	\N	1	5	2025-10-02 17:41:17.946665+00	\N	\N	\N	\N	2025-10-02 17:41:17.946665+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	e2e ingreso
36313858-e96e-4657-8782-64e3bea71922	\N	egreso	\N	\N	1	3	2025-10-02 17:41:17.971643+00	\N	\N	\N	\N	2025-10-02 17:41:17.971643+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	e2e egreso
74326ce0-b32b-492e-847c-e71aef5e85b6	\N	egreso	\N	\N	1	2	2025-10-02 17:41:17.990995+00	\N	\N	\N	\N	2025-10-02 17:41:17.990995+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] e2e set=2
325bc34a-0430-4afd-9d62-74db48e85cea	\N	ingreso	\N	\N	1	1	2025-10-02 17:44:55.957775+00	\N	\N	\N	\N	2025-10-02 17:44:55.957775+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	probe
00f202b4-d5cc-4f28-a72d-6bf495ac5a2b	\N	ingreso	\N	\N	1	5	2025-10-02 18:13:36.920377+00	\N	\N	\N	\N	2025-10-02 18:13:36.920377+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	smoke ingreso
142db621-4e66-484b-802a-6fe93a589440	\N	egreso	\N	\N	1	3	2025-10-02 18:13:36.965062+00	\N	\N	\N	\N	2025-10-02 18:13:36.965062+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	smoke egreso
de3799d5-2e5a-4d96-8a4c-73bec3293ae6	\N	egreso	\N	\N	1	3	2025-10-02 18:13:37.010586+00	\N	\N	\N	\N	2025-10-02 18:13:37.010586+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] smoke set=2
09cfb9e0-fa7d-4460-9761-68d3f2fbe64b	\N	ingreso	\N	\N	1	5	2025-10-02 19:31:53.558251+00	\N	\N	\N	\N	2025-10-02 19:31:53.558251+00	\N	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	ingreso con key
1124dad2-63f7-474b-9561-dab4ab30de85	\N	egreso	\N	\N	1	3	2025-10-02 19:31:53.600221+00	\N	\N	\N	\N	2025-10-02 19:31:53.600221+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	egreso con key
1fd43943-ff07-4d23-a567-da30368194c8	\N	egreso	\N	\N	1	2	2025-10-02 19:31:53.651218+00	\N	\N	\N	\N	2025-10-02 19:31:53.651218+00	bdf0d98a-f0ee-4f42-a761-11be1a352e61	\N	\N	[ajuste] ajuste set=2 con key
\.


--
-- Data for Name: orden_evidencias; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.orden_evidencias (id, orden_id, tipo, url, created_at) FROM stdin;
\.


--
-- Data for Name: orden_materiales; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.orden_materiales (id, material_id, cantidad, descontado, created_at, updated_at, orden_id) FROM stdin;
07cef21e-cd70-4022-8f31-4934972326e5	1	2	t	2025-09-30 12:49:00.620086+00	2025-09-30 12:54:24.164761+00	39f2d006-2426-4bc7-8ab9-2c0f12ed7b55
ed1b7356-3787-4679-93ab-fe1e5b1a44f7	1	1	t	2025-09-30 13:08:18.118163+00	2025-09-30 13:08:18.118163+00	3b43c017-4f54-4991-b262-20c3f541f0e0
\.


--
-- Data for Name: ordenes; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.ordenes (id, codigo, tipo, estado, agendado_para, turno, agendada_at, iniciada_at, cerrada_at, cancelada_at, motivo_cancelacion, usuario_id, tecnico_id, venta_id, motivo_anulacion, motivo_anulacion_id) FROM stdin;
13669d5d-4795-46ec-9d50-e5dd6f09b89c	MAN-250929183814	MAN	agendada	2025-09-29	am	2025-09-29 23:38:15.132512+00	\N	\N	\N	\N	\N	\N	\N	\N	\N
788d8139-63ec-495c-b435-fb7388da0345	MAN-250929184104	MAN	agendada	2025-09-29	am	2025-09-29 23:41:04.571575+00	\N	\N	\N	\N	\N	\N	\N	\N	\N
db409509-f160-492b-97c8-fd89623ef532	MAN-250929184325	MAN	en_progreso	2025-09-29	am	2025-09-29 23:43:25.38684+00	2025-09-29 23:43:25.511+00	\N	\N	\N	\N	\N	\N	\N	\N
a91657cc-c497-4a9e-8586-79427608304b	MAN-250929184613	MAN	en_progreso	2025-09-29	am	2025-09-29 23:46:13.546077+00	2025-09-29 23:46:13.654+00	\N	\N	\N	\N	\N	\N	\N	\N
69e0b78e-c966-47dc-a824-8885d44f573b	MAN-250929184850	MAN	asignada	2025-09-29	am	2025-09-29 23:48:51.160446+00	\N	\N	\N	\N	\N	\N	\N	\N	\N
0a60d80b-afb3-4f4c-a4db-aaf74dee2073	MAN-250929185110	MAN	en_progreso	2025-09-29	am	2025-09-29 23:51:11.233006+00	2025-09-29 23:51:11.308+00	\N	\N	\N	\N	\N	\N	\N	\N
484decaa-d5b5-4e28-b933-872a2bab187a	MAN-250929185335	MAN	en_progreso	2025-09-29	am	2025-09-29 23:53:35.738384+00	2025-09-29 23:53:35.816+00	\N	\N	\N	\N	\N	\N	\N	\N
4e943e52-5495-4d1f-8f81-4863764a2e31	INS-000006	INS	anulada	2025-10-11	PM	2025-10-01 18:02:47.158131+00	\N	\N	2025-10-01 18:02:47.217476+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
46005e47-8106-4532-ae71-4a155f5e89bc	INS-000007	INS	anulada	2025-10-11	PM	2025-10-01 18:21:37.261788+00	\N	\N	2025-10-01 18:21:37.380281+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
e87fa98f-17ca-4630-b15b-b5df90699f9b	INS-000008	INS	anulada	2025-10-11	PM	2025-10-01 18:22:58.340392+00	\N	\N	2025-10-01 18:22:58.408904+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
3b43c017-4f54-4991-b262-20c3f541f0e0	MAN-250930130817	INS	cerrada	\N	\N	\N	2025-09-30 13:08:18.028+00	2025-09-30 13:08:18.118163+00	\N	\N	\N	\N	\N	\N	\N
21b20738-78b8-47a7-8acd-200df3cfe51d	INS-000001	INS	anulada	2025-10-03	AM	2025-10-01 15:55:34.677976+00	\N	\N	2025-10-01 15:55:34.785142+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	\N
d90e5982-1c6c-4b2e-9471-c5e1f9f4eeb1	INS-000009	INS	anulada	2025-10-11	PM	2025-10-02 00:18:10.891877+00	\N	\N	2025-10-02 00:18:10.958789+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
5ad63233-3d1b-455a-9ec8-f1f1e6477d88	INS-000002	INS	anulada	2025-10-06	PM	2025-10-01 16:21:59.49121+00	\N	\N	2025-10-01 16:21:59.540688+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	\N
39f2d006-2426-4bc7-8ab9-2c0f12ed7b55	MAN-250929192117	INS	anulada	2025-09-29	AM	\N	2025-09-30 00:21:51.503+00	2025-09-30 12:54:24.164761+00	2025-10-01 16:51:52.731705+00	normalizacion: unica INS activa	\N	\N	\N	\N	\N
6924030b-3195-4005-a30e-17e6ba0668e0	INS-000003	INS	anulada	2025-10-08	PM	2025-10-01 16:55:08.390567+00	\N	\N	2025-10-01 16:55:08.434332+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
c4b04ccd-ca6c-4bc9-a4a7-18d3d8ac90a5	INS-000010	INS	anulada	2025-10-11	PM	2025-10-02 00:21:43.082727+00	\N	\N	2025-10-02 00:21:43.146197+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
a104f6ee-5663-4dea-a8ce-4b4982ba5eaf	INS-000004	INS	anulada	2025-10-11	PM	2025-10-01 17:56:05.903651+00	\N	\N	2025-10-01 17:56:05.977452+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
1de8f6aa-bbac-41dc-912b-a9815b5486cf	INS-000011	INS	anulada	2025-10-11	PM	2025-10-02 00:40:36.654667+00	\N	\N	2025-10-02 00:40:36.777709+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
15ad6e0f-9611-49e0-ad92-c46b13af9474	INS-000005	INS	anulada	2025-10-11	PM	2025-10-01 17:58:11.508798+00	\N	\N	2025-10-01 17:58:11.575054+00	Cliente no disponible	\N	\N	f3bc413e-defc-4dbe-9955-a65d5d926da2	\N	5
\.


--
-- Data for Name: ordenes_datos_tecnicos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.ordenes_datos_tecnicos (orden_id, plan_codigo, plan_nombre, incluye_tv, pon_sn, onu_estandar, repetidor_mac, con_roseta, marquilla, updated_at) FROM stdin;
\.


--
-- Data for Name: ordenes_evidencias; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.ordenes_evidencias (id, orden_id, tipo, obj_key, created_at) FROM stdin;
\.


--
-- Data for Name: ordenes_pdf; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.ordenes_pdf (orden_id, acta_pdf_key, generado_at) FROM stdin;
\.


--
-- Data for Name: stock_almacen; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.stock_almacen (almacen_id, material_id, cantidad, updated_at, created_at) FROM stdin;
bdf0d98a-f0ee-4f42-a761-11be1a352e61	3	10	2025-10-02 00:40:37.372347+00	2025-10-01 23:50:26.658408+00
a1f107e4-2184-4d88-aa04-39d31aa0c02d	3	1	2025-10-02 00:40:37.372347+00	2025-10-02 00:01:46.553693+00
bdf0d98a-f0ee-4f42-a761-11be1a352e61	1	2	2025-10-02 19:31:53.651218+00	2025-10-02 16:48:21.412162+00
beb7a8f6-28a2-4ad2-b121-5619580ba82d	1	0	\N	2025-10-01 23:50:26.658408+00
\.


--
-- Data for Name: tecnicos; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.tecnicos (id, nombre, codigo, activo, created_at, updated_at) FROM stdin;
1	Técnico 1	TEC-1	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
2	Técnico 2	TEC-2	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
3	Técnico 3	TEC-3	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
4	Técnico 4	TEC-4	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
5	Técnico 5	TEC-5	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
6	Técnico 6	TEC-6	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
7	Técnico 7	TEC-7	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
8	Técnico 8	TEC-8	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
9	Técnico 9	TEC-9	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
10	Técnico 10	TEC-10	t	2025-10-01 22:49:21.211406+00	2025-10-01 22:49:21.213436+00
11	Tecnico CI	TEC-0006	t	2025-10-01 22:58:26.951357+00	2025-10-01 22:58:26.951357+00
\.


--
-- Data for Name: venta_pagos_idem; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.venta_pagos_idem (id, idem_key, venta_id, created_at) FROM stdin;
36558671-6e48-4351-ad4e-40b318ea66f9	pay-1759332800011	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:33:20.022135+00
2f96cb37-6013-4032-82dd-90e1f32cfe57	pay-1759333117527	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:38:37.538457+00
5033348c-1496-4053-af73-d60ccc2acc54	pay-1759333363423	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:42:43.433846+00
f6a43646-225c-4376-b7c3-ab64d6142fbd	pay-1759333650012	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:47:30.024099+00
b5f05511-e81f-4cc5-ad12-13a8231be164	pay-1759333753722	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:49:13.733319+00
c02e568f-3080-4038-9f34-de9d7e0912f3	pay-1759333812289	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 15:50:12.299265+00
f573c393-3e79-40e3-96ea-1abed986b439	pay-1759335359062	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 16:15:59.07247+00
0d849f51-fa9e-4e08-80e4-24d44c674c6c	k1759335645817	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 16:20:45.83111+00
b3104da8-1277-4606-929e-4cc256b85220	pay-1759337596834	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 16:53:16.84447+00
413e5d22-158d-47d8-8844-b59faa51b471	pay-1759339835105	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:30:35.116217+00
e69e79a9-440e-41fe-b5d5-65292afedff1	pay-1759340175458	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:36:15.469394+00
319a17f5-8445-4963-a5cf-7bf2ddb121b3	pay-1759340501768	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:41:41.777593+00
0e6a0d00-6062-4a38-a2fc-1352a5494fd2	pay-1759340802912	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:46:42.92296+00
a5421bcf-6451-41a9-b8a4-524b2953a7c6	pay-1759340910024	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:48:30.032595+00
4bde9d4a-ca5b-43a0-9760-9987bdcc528a	pay-1759341065313	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:51:05.322506+00
440f6a14-f0ea-4fa3-93e3-be0c82a00423	pay-1759341216680	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:53:36.692813+00
9ab69e29-c627-43b3-beba-c2668c7cbb44	pay-1759341325271	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:55:25.281481+00
674274f6-a87b-43b5-b790-83f14c7e3afd	pay-1759341490920	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 17:58:10.930227+00
1363a117-5ee0-4316-abe8-52102542e9c7	pay-1759341766185	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 18:02:46.194275+00
8f38397d-7838-47b2-b68c-fe1102a1a654	pay-1759341766612	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 18:02:46.621246+00
6e0c693b-5bd6-427d-841f-ab2d3ff17fcf	pay-1759342896255	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 18:21:36.266329+00
21c009c0-720b-4c44-81d0-d2c315e00e4b	pay-1759342896681	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 18:21:36.691496+00
9a10b056-e31c-4b36-9651-a52c1150e590	pay-1759342977755	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-01 18:22:57.764804+00
75e4ad9e-d1bd-4af0-8eb8-3fb0e59471a8	pay-1759364289827	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-02 00:18:09.837725+00
ff583e80-c97e-4d9e-b5cd-99b3118cc276	pay-1759364290253	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-02 00:18:10.262906+00
675a76e9-5fde-41ed-8290-abbdf5ced0a5	pay-1759364502097	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-02 00:21:42.108069+00
b6d7a554-f06e-4265-9bd4-22ffc04a97f6	pay-1759364502515	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-02 00:21:42.524435+00
ab0aa0c5-55a0-4604-b48a-35404c66884c	pay-1759365636087	f3bc413e-defc-4dbe-9955-a65d5d926da2	2025-10-02 00:40:36.097451+00
\.


--
-- Data for Name: ventas; Type: TABLE DATA; Schema: public; Owner: ispuser
--

COPY public.ventas (id, codigo, cliente_nombre, cliente_apellido, documento, usuario_id, estado, plan, mensual_total, total, recibo_pdf_key, contrato_pdf_key, created_at, cedula_img_key, recibo_img_key, firma_img_key) FROM stdin;
f3bc413e-defc-4dbe-9955-a65d5d926da2	VTA-202510-0001	Ana	Pérez	CC123	8bc839af-8f75-410e-b02e-adbc46d88b3b	pagada	FTTH 100M	30.00	30.00	\N	\N	2025-10-01 14:42:39.671409+00	evidencias/ventas/CC123/cedula.png	evidencias/ventas/CC123/recibo.png	evidencias/ventas/CC123/firma.png
\.


--
-- Name: catalogo_motivos_anulacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ispuser
--

SELECT pg_catalog.setval('public.catalogo_motivos_anulacion_id_seq', 5, true);


--
-- Name: catalogo_motivos_reagenda_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ispuser
--

SELECT pg_catalog.setval('public.catalogo_motivos_reagenda_id_seq', 49, true);


--
-- Name: materiales_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ispuser
--

SELECT pg_catalog.setval('public.materiales_id_seq', 4, true);


--
-- Name: tecnicos_id_seq; Type: SEQUENCE SET; Schema: public; Owner: ispuser
--

SELECT pg_catalog.setval('public.tecnicos_id_seq', 11, true);


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
-- Name: idx_stock_almacen_material; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_stock_almacen_material ON public.stock_almacen USING btree (material_id);


--
-- Name: idx_stock_almacen_updated; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX idx_stock_almacen_updated ON public.stock_almacen USING btree (updated_at);


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
-- Name: ix_ordenes_motivo_anulacion; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_ordenes_motivo_anulacion ON public.ordenes USING btree (estado) WHERE (motivo_anulacion IS NOT NULL);


--
-- Name: ix_stock_almacen_almacen; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_stock_almacen_almacen ON public.stock_almacen USING btree (almacen_id);


--
-- Name: ix_stock_almacen_mat; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_stock_almacen_mat ON public.stock_almacen USING btree (material_id);


--
-- Name: ix_venta_pagos_idem_venta; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE INDEX ix_venta_pagos_idem_venta ON public.venta_pagos_idem USING btree (venta_id, created_at DESC);


--
-- Name: ux_orden_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_codigo ON public.ordenes USING btree (codigo);


--
-- Name: ux_orden_ins_activa; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_ins_activa ON public.ordenes USING btree (venta_id) WHERE ((tipo = 'INS'::text) AND (estado <> 'anulada'::text));


--
-- Name: ux_orden_unica_ins_venta_activa; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_orden_unica_ins_venta_activa ON public.ordenes USING btree (venta_id) WHERE ((tipo = 'INS'::text) AND (estado <> 'anulada'::text));


--
-- Name: ux_venta_pagos_idem_key; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_venta_pagos_idem_key ON public.venta_pagos_idem USING btree (idem_key);


--
-- Name: ux_ventas_codigo; Type: INDEX; Schema: public; Owner: ispuser
--

CREATE UNIQUE INDEX ux_ventas_codigo ON public.ventas USING btree (codigo);


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
-- Name: movimientos trg_movimientos_guardrail_saldo; Type: TRIGGER; Schema: public; Owner: ispuser
--

CREATE TRIGGER trg_movimientos_guardrail_saldo BEFORE INSERT ON public.movimientos FOR EACH ROW EXECUTE FUNCTION public.fn_movimientos_guardrail_saldo();


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

\unrestrict uefRVQ8K5VMGPFAe4s3tMpU2N4b6sZCHZ02S5hL0D0lMhWwj4hT0B9BmpyIetC7

