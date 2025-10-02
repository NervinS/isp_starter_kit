CREATE TABLE IF NOT EXISTS equipos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL CHECK (tipo IN ('ONU','REPETIDOR')),
  sn TEXT UNIQUE,
  mac TEXT UNIQUE,
  estandar TEXT CHECK (estandar IN ('wifi4','wifi5','wifi6','wifi7')),
  estado TEXT NOT NULL DEFAULT 'EN_STOCK'
         CHECK (estado IN ('EN_STOCK','ASIGNADO_TECNICO','ASIGNADO_USUARIO','RETIRADO')),
  owner_tipo TEXT NOT NULL DEFAULT 'ALMACEN'
            CHECK (owner_tipo IN ('ALMACEN','TECNICO','USUARIO')),
  owner_id TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_equipo_tipo ON equipos(tipo);
CREATE INDEX IF NOT EXISTS ix_equipo_owner ON equipos(owner_tipo, owner_id);

CREATE TABLE IF NOT EXISTS equipos_movs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  equipo_id UUID NOT NULL REFERENCES equipos(id) ON DELETE CASCADE,
  from_owner_tipo TEXT CHECK (from_owner_tipo IN ('ALMACEN','TECNICO','USUARIO')),
  from_owner_id TEXT,
  to_owner_tipo TEXT CHECK (to_owner_tipo IN ('ALMACEN','TECNICO','USUARIO')),
  to_owner_id TEXT,
  motivo TEXT,
  orden_id UUID REFERENCES ordenes(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_eqm_equipo ON equipos_movs(equipo_id);
CREATE INDEX IF NOT EXISTS ix_eqm_to ON equipos_movs(to_owner_tipo, to_owner_id);
