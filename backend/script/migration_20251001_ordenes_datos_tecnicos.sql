CREATE TABLE IF NOT EXISTS ordenes_datos_tecnicos (
  orden_id UUID PRIMARY KEY REFERENCES ordenes(id) ON DELETE CASCADE,
  plan_codigo TEXT,
  plan_nombre TEXT,
  incluye_tv BOOLEAN,
  pon_sn TEXT,
  onu_estandar TEXT CHECK (onu_estandar IN ('wifi4','wifi5','wifi6','wifi7')),
  repetidor_mac TEXT,
  con_roseta BOOLEAN,
  marquilla TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ix_odt_onu_estandar') THEN
    CREATE INDEX ix_odt_onu_estandar ON ordenes_datos_tecnicos(onu_estandar);
  END IF;
END$$;
