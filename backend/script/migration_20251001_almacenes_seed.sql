-- Normaliza estructura si la tabla ya existía con otro esquema
CREATE TABLE IF NOT EXISTS almacenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT,
  nombre TEXT,
  tipo   TEXT,
  activo BOOLEAN,
  created_at TIMESTAMPTZ
);

-- Asegura columnas clave (si faltaran)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='codigo') THEN
    ALTER TABLE almacenes ADD COLUMN codigo TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='nombre') THEN
    ALTER TABLE almacenes ADD COLUMN nombre TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='tipo') THEN
    ALTER TABLE almacenes ADD COLUMN tipo TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='activo') THEN
    ALTER TABLE almacenes ADD COLUMN activo BOOLEAN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='almacenes' AND column_name='created_at') THEN
    ALTER TABLE almacenes ADD COLUMN created_at TIMESTAMPTZ;
  END IF;
END$$;

-- Defaults y NOT NULL seguros
ALTER TABLE almacenes ALTER COLUMN tipo       SET DEFAULT 'principal';
UPDATE almacenes SET tipo='principal'     WHERE tipo       IS NULL;

ALTER TABLE almacenes ALTER COLUMN activo     SET DEFAULT TRUE;
UPDATE almacenes SET activo=TRUE          WHERE activo     IS NULL;

ALTER TABLE almacenes ALTER COLUMN created_at SET DEFAULT now();
UPDATE almacenes SET created_at=now()     WHERE created_at IS NULL;

-- Si quieres los NOT NULL (opcional; comenta si prefieres permitir NULLs legados)
ALTER TABLE almacenes ALTER COLUMN tipo       SET NOT NULL;
ALTER TABLE almacenes ALTER COLUMN activo     SET NOT NULL;
ALTER TABLE almacenes ALTER COLUMN created_at SET NOT NULL;

-- Limpia índice único parcial viejo si existiera
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_almacenes_codigo') THEN
    DROP INDEX ux_almacenes_codigo;
  END IF;
END$$;

-- Crea UNIQUE CONSTRAINT real (para ON CONFLICT (codigo))
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname='uq_almacenes_codigo'
      AND conrelid='almacenes'::regclass
  ) THEN
    ALTER TABLE almacenes ADD CONSTRAINT uq_almacenes_codigo UNIQUE (codigo);
  END IF;
END$$;

-- Upsert del almacén PRINCIPAL
INSERT INTO almacenes (codigo, nombre, tipo, activo)
VALUES ('PRINCIPAL','Almacén Principal','principal', TRUE)
ON CONFLICT (codigo) DO NOTHING;

-- Fallback defensivo
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM almacenes WHERE codigo='PRINCIPAL') THEN
    INSERT INTO almacenes (codigo, nombre, tipo, activo)
    VALUES ('PRINCIPAL','Almacén Principal','principal', TRUE);
  END IF;
END$$;
