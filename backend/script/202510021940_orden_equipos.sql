-- migration ...202510021940_orden_equipos.sql
CREATE TABLE IF NOT EXISTS orden_equipos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL REFERENCES ordenes(id) ON DELETE CASCADE,
  equipo_tipo TEXT NOT NULL CHECK (equipo_tipo IN ('ONT','REPEATER')),
  serial TEXT NOT NULL,
  accion TEXT NOT NULL CHECK (accion IN ('asignar','retirar','mantener')),
  aplicado BOOLEAN NOT NULL DEFAULT false, -- para idempotencia del cierre
  UNIQUE (orden_id, equipo_tipo, serial)   -- evita duplicados
);
CREATE INDEX IF NOT EXISTS ix_orden_equipos_orden ON orden_equipos(orden_id);
