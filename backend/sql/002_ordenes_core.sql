-- sql/002_ordenes_core.sql
-- Núcleo de órdenes: columnas, eventos, generador de códigos y trigger robusto/idempotente

-- 1) Columnas requeridas por backend (idempotente)
ALTER TABLE ordenes
  ADD COLUMN IF NOT EXISTS iniciada_at timestamptz,
  ADD COLUMN IF NOT EXISTS cerrada_at  timestamptz,
  ADD COLUMN IF NOT EXISTS firma_key   text,
  ADD COLUMN IF NOT EXISTS pdf_url     text;

-- 2) Tabla de eventos (idempotente)
CREATE TABLE IF NOT EXISTS ordenes_eventos(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo     text NOT NULL,
  evento     text NOT NULL,
  payload    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  tecnico_id uuid NULL
);

-- Índices
CREATE INDEX IF NOT EXISTS ix_ordenes_eventos_codigo_created_at ON ordenes_eventos(codigo, created_at);
CREATE INDEX IF NOT EXISTS ix_ordenes_eventos_tecnico           ON ordenes_eventos(tecnico_id, created_at DESC);

-- Dominio de evento (NOT VALID para no bloquear histórico)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'ordenes_eventos'::regclass
      AND conname  = 'ck_ordenes_evento_dom'
  ) THEN
    ALTER TABLE ordenes_eventos
      ADD CONSTRAINT ck_ordenes_evento_dom
      CHECK (evento IN ('iniciar','cerrar','solicitar_reagenda')) NOT VALID;
  END IF;
END$$;

-- 3) Secuencias por tipo (idempotente)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_ins') THEN CREATE SEQUENCE seq_orden_ins START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_man') THEN CREATE SEQUENCE seq_orden_man START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_cor') THEN CREATE SEQUENCE seq_orden_cor START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_rec') THEN CREATE SEQUENCE seq_orden_rec START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_baj') THEN CREATE SEQUENCE seq_orden_baj START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_tra') THEN CREATE SEQUENCE seq_orden_tra START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_cmb') THEN CREATE SEQUENCE seq_orden_cmb START 1; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='seq_orden_rct') THEN CREATE SEQUENCE seq_orden_rct START 1; END IF;
END$$;

-- 4) Generador de código por tipo (con cero-pad correcto)
CREATE OR REPLACE FUNCTION fn_ordenes_next_codigo(p_tipo text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  n bigint; pref text;
BEGIN
  CASE p_tipo
    WHEN 'INS' THEN pref:='INS'; n:=nextval('seq_orden_ins');
    WHEN 'MAN' THEN pref:='MAN'; n:=nextval('seq_orden_man');
    WHEN 'COR' THEN pref:='COR'; n:=nextval('seq_orden_cor');
    WHEN 'REC' THEN pref:='REC'; n:=nextval('seq_orden_rec');
    WHEN 'BAJ' THEN pref:='BAJ'; n:=nextval('seq_orden_baj');
    WHEN 'TRA' THEN pref:='TRA'; n:=nextval('seq_orden_tra');
    WHEN 'CMB' THEN pref:='CMB'; n:=nextval('seq_orden_cmb');
    WHEN 'RCT' THEN pref:='RCT'; n:=nextval('seq_orden_rct');
    ELSE
      RAISE EXCEPTION 'Tipo inválido %', p_tipo;
  END CASE;

  -- OJO: format('%06s', n) no hace zero-pad en enteros.
  -- Usar to_char para relleno: 000001, 000002, etc.
  RETURN format('%s-%s', pref, to_char(n, 'FM000000'));
END$$;

-- 5) Trigger BEFORE INSERT robusto
CREATE OR REPLACE FUNCTION trg_ordenes_set_codigo_bi()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- Si no hay tipo, no podemos generar; deja el código como venga (seeds especiales).
  IF NEW.tipo IS NULL THEN
    RETURN NEW;
  END IF;

  -- Respeta códigos "seed" explícitos
  IF NEW.codigo IS NOT NULL AND NEW.codigo LIKE 'ORD-SEED-%' THEN
    RETURN NEW;
  END IF;

  -- Genera si falta o no cumple el formato estándar
  IF NEW.codigo IS NULL
     OR btrim(NEW.codigo) = ''
     OR NEW.codigo !~ '^(INS|MAN|COR|REC|BAJ|TRA|CMB|RCT)-[0-9]{6}$'
  THEN
    NEW.codigo := fn_ordenes_next_codigo(NEW.tipo);
  END IF;

  RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS ordenes_set_codigo_bi ON ordenes;
CREATE TRIGGER ordenes_set_codigo_bi
BEFORE INSERT ON ordenes
FOR EACH ROW
EXECUTE FUNCTION trg_ordenes_set_codigo_bi();
