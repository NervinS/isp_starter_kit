-- Stock por almacén
CREATE TABLE IF NOT EXISTS stock_almacen (
  id           BIGSERIAL PRIMARY KEY,
  almacen_id   UUID NOT NULL REFERENCES almacenes(id) ON DELETE CASCADE,
  material_id  INTEGER NOT NULL REFERENCES materiales(id) ON DELETE RESTRICT,
  cantidad     NUMERIC(14,2) NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (almacen_id, material_id)
);
CREATE INDEX IF NOT EXISTS ix_stock_almacen_almacen ON stock_almacen(almacen_id);
CREATE INDEX IF NOT EXISTS ix_stock_almacen_mat     ON stock_almacen(material_id);

-- Movimientos: crea si no existe; si existe, normaliza columnas faltantes
CREATE TABLE IF NOT EXISTS movimientos (
  id              BIGSERIAL PRIMARY KEY
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
              WHERE table_schema='public' AND table_name='movimientos') THEN

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='fecha') THEN
      ALTER TABLE movimientos ADD COLUMN fecha TIMESTAMPTZ NOT NULL DEFAULT now();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='tipo') THEN
      ALTER TABLE movimientos ADD COLUMN tipo TEXT;
      UPDATE movimientos SET tipo='ingreso' WHERE tipo IS NULL;
      ALTER TABLE movimientos ALTER COLUMN tipo SET NOT NULL;
      ALTER TABLE movimientos ADD CONSTRAINT chk_mov_tipo
        CHECK (tipo IN ('ingreso','egreso','ajuste','traslado','devolucion'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='material_id') THEN
      ALTER TABLE movimientos ADD COLUMN material_id INTEGER REFERENCES materiales(id) ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='cantidad') THEN
      ALTER TABLE movimientos ADD COLUMN cantidad NUMERIC(14,2) NOT NULL DEFAULT 0;
      ALTER TABLE movimientos ADD CONSTRAINT chk_mov_cantidad CHECK (cantidad >= 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='from_almacen_id') THEN
      ALTER TABLE movimientos ADD COLUMN from_almacen_id UUID REFERENCES almacenes(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='to_almacen_id') THEN
      ALTER TABLE movimientos ADD COLUMN to_almacen_id UUID REFERENCES almacenes(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='tecnico_id') THEN
      ALTER TABLE movimientos ADD COLUMN tecnico_id INTEGER REFERENCES tecnicos(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='movimientos' AND column_name='nota') THEN
      ALTER TABLE movimientos ADD COLUMN nota TEXT;
    END IF;

  END IF;
END$$;

-- Índices (ya con columnas garantizadas)
CREATE INDEX IF NOT EXISTS ix_mov_fecha        ON movimientos(fecha DESC);
CREATE INDEX IF NOT EXISTS ix_mov_material     ON movimientos(material_id);
CREATE INDEX IF NOT EXISTS ix_mov_from_almacen ON movimientos(from_almacen_id);
CREATE INDEX IF NOT EXISTS ix_mov_to_almacen   ON movimientos(to_almacen_id);
CREATE INDEX IF NOT EXISTS ix_mov_tipo         ON movimientos(tipo);

-- Vista base de kárdex
CREATE OR REPLACE VIEW v_kardex AS
SELECT
  m.id,
  m.fecha,
  m.tipo,
  m.material_id,
  m.cantidad,
  COALESCE(m.to_almacen_id, m.from_almacen_id) AS almacen_id,
  CASE
    WHEN m.tipo IN ('ingreso','devolucion') AND m.to_almacen_id IS NOT NULL THEN  m.cantidad
    WHEN m.tipo='ajuste' THEN m.cantidad
    WHEN m.tipo IN ('egreso')  AND m.from_almacen_id IS NOT NULL THEN -m.cantidad
    WHEN m.tipo='traslado' AND m.to_almacen_id   IS NOT NULL THEN  m.cantidad
    WHEN m.tipo='traslado' AND m.from_almacen_id IS NOT NULL THEN -m.cantidad
    ELSE 0
  END AS delta,
  m.from_almacen_id,
  m.to_almacen_id,
  m.tecnico_id,
  m.nota
FROM movimientos m;
