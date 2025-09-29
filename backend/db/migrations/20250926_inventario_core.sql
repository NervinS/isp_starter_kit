-- 20250926_inventario_core.sql
-- Inventario Core: materiales, almacenes, stock_almacen, movimientos, v_kardex

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =========================
-- Catálogo de materiales
-- =========================
CREATE TABLE IF NOT EXISTS materiales (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku              text NOT NULL UNIQUE,
  nombre           text NOT NULL,
  uom              text NOT NULL DEFAULT 'unidad',
  serie_required   boolean NOT NULL DEFAULT false,
  activo           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- =========================
-- Almacenes (principal / técnico)
-- =========================
CREATE TABLE IF NOT EXISTS almacenes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo        text NOT NULL CHECK (tipo IN ('principal','tecnico')),
  tecnico_id  uuid NULL,              -- FK opcional a tecnicos.* si aplica
  nombre      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =========================
-- Stock por almacén/material
-- =========================
CREATE TABLE IF NOT EXISTS stock_almacen (
  almacen_id  uuid NOT NULL,
  material_id uuid NOT NULL,
  cantidad    numeric(18,6) NOT NULL DEFAULT 0,
  PRIMARY KEY (almacen_id, material_id),
  CONSTRAINT fk_stock_almacen
    FOREIGN KEY (almacen_id) REFERENCES almacenes(id) ON DELETE CASCADE,
  CONSTRAINT fk_stock_material
    FOREIGN KEY (material_id) REFERENCES materiales(id) ON DELETE RESTRICT,
  CONSTRAINT chk_cantidad_nonnull CHECK (cantidad IS NOT NULL)
);

-- =========================
-- Movimientos (Kardex)
-- =========================
CREATE TABLE IF NOT EXISTS movimientos (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key     text UNIQUE NOT NULL,
  tipo                text NOT NULL CHECK (tipo IN ('ingreso','egreso','transferencia','ajuste')),
  almacen_origen_id   uuid NULL,
  almacen_destino_id  uuid NULL,
  material_id         uuid NOT NULL REFERENCES materiales(id),
  cantidad            numeric(18,6) NOT NULL CHECK (cantidad > 0),
  motivo              text,
  ref_externa         text,
  evidencia_key       text,
  usuario_op_id       uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  -- Valida combinaciones por tipo
  CONSTRAINT chk_mov_combinaciones CHECK (
    (tipo='ingreso'       AND almacen_destino_id IS NOT NULL)
 OR (tipo='egreso'        AND almacen_origen_id  IS NOT NULL)
 OR (tipo='transferencia' AND almacen_origen_id  IS NOT NULL AND almacen_destino_id IS NOT NULL AND almacen_origen_id <> almacen_destino_id)
 OR (tipo='ajuste')
  )
);

-- =========================
-- Vista de Kardex (saldo acumulado)
-- Nota: para 'ajuste' el signo se gestiona a nivel de Service;
-- aquí asumimos 'cantidad' positiva; el delta se pasará con signo.
-- =========================
DROP VIEW IF EXISTS v_kardex;
CREATE VIEW v_kardex AS
WITH base AS (
  -- ingresos / egresos simples
  SELECT
    m.almacen_destino_id AS almacen_id,
    m.material_id,
    m.cantidad            AS delta,
    m.created_at,
    'ingreso'::text       AS etiqueta
  FROM movimientos m
  WHERE m.tipo='ingreso'

  UNION ALL

  SELECT
    m.almacen_origen_id   AS almacen_id,
    m.material_id,
    -m.cantidad           AS delta,
    m.created_at,
    'egreso'::text        AS etiqueta
  FROM movimientos m
  WHERE m.tipo='egreso'

  UNION ALL

  -- transferencias (salida)
  SELECT
    m.almacen_origen_id   AS almacen_id,
    m.material_id,
    -m.cantidad           AS delta,
    m.created_at,
    'transferencia_out'::text AS etiqueta
  FROM movimientos m
  WHERE m.tipo='transferencia'

  UNION ALL

  -- transferencias (entrada)
  SELECT
    m.almacen_destino_id  AS almacen_id,
    m.material_id,
    m.cantidad            AS delta,
    m.created_at,
    'transferencia_in'::text AS etiqueta
  FROM movimientos m
  WHERE m.tipo='transferencia'

  UNION ALL

  -- ajustes: acá se suma como positivo;
  -- el Service debe guardar 'cantidad' positiva y aplicar signo al delta real.
  SELECT
    COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
    m.material_id,
    m.cantidad AS delta,
    m.created_at,
    'ajuste'::text AS etiqueta
  FROM movimientos m
  WHERE m.tipo='ajuste'
)
SELECT
  b.almacen_id,
  b.material_id,
  b.delta,
  b.created_at,
  b.etiqueta,
  SUM(b.delta) OVER (PARTITION BY b.almacen_id, b.material_id ORDER BY b.created_at
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS saldo_acumulado
FROM base b
ORDER BY b.created_at;

-- =========================
-- Índices de soporte
-- =========================
CREATE INDEX IF NOT EXISTS idx_movimientos_material_fecha ON movimientos(material_id, created_at);
CREATE INDEX IF NOT EXISTS idx_movimientos_origen ON movimientos(almacen_origen_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_destino ON movimientos(almacen_destino_id);
CREATE INDEX IF NOT EXISTS idx_stock_tipo ON stock_almacen(almacen_id, material_id);
