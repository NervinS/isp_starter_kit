BEGIN;

-- =========================================================
-- 1) NO cambiamos tipo de "estado" (mantener TEXT).
--    Solo nos aseguramos de defaults/índices coherentes.
-- =========================================================

-- Asegura default 'agendada' como text (solo si hoy no hay default)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_attrdef d
    JOIN pg_class c ON c.oid = d.adrelid
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.adnum
    WHERE c.relname = 'ordenes' AND a.attname = 'estado'
  ) THEN
    ALTER TABLE ordenes ALTER COLUMN estado SET DEFAULT 'agendada';
  END IF;
END$$;

-- Índice por estado (si no existía)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'ix_ordenes_estado') THEN
    CREATE INDEX ix_ordenes_estado ON ordenes(estado);
  END IF;
END$$;

-- =========================================================
-- 2) Tabla orden_evidencias (si no existe)
-- =========================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='orden_evidencias') THEN
    CREATE TABLE orden_evidencias (
      id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
      orden_id    uuid NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
      tipo        text NOT NULL CHECK (tipo IN ('foto','firma','otro')),
      url         text NOT NULL,
      meta        jsonb,
      created_at  timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX ix_oe_orden ON orden_evidencias(orden_id);
    CREATE INDEX ix_oe_tipo  ON orden_evidencias(tipo);
  END IF;
END$$;

-- =========================================================
-- 3) Semillas mínimas de materiales (códigos esperados por técnicos)
--    Solo inserta si no existen
-- =========================================================
-- Materiales esperados (ejemplo de catálogo base)
-- DROP (metros), CONECT_FO, CONECT_RG6, PATCHCORD, UTP (metros), ROSETA, REPETIDOR, ONU
WITH base(code, nombre, unidad_defecto, precio) AS (
  VALUES
   ('DROP','Drop FO domiciliario','mts', 0),
   ('CONECT_FO','Conector FO','und', 0),
   ('CONECT_RG6','Conector RG6','und', 0),
   ('PATCHCORD','Patchcord','und', 0),
   ('UTP','Cable UTP','mts', 0),
   ('ROSETA','Roseta terminal','und', 0),
   ('REPETIDOR','Repetidor WiFi','und', 0),
   ('ONU','ONU/ONT','und', 0)
)
INSERT INTO materiales(codigo, nombre, unidad_defecto, precio)
SELECT b.code, b.nombre, b.unidad_defecto, b.precio
FROM base b
LEFT JOIN materiales m ON m.codigo = b.code
WHERE m.id IS NULL;

COMMIT;
