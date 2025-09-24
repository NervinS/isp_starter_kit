-- sql/2025-09-19_init_inventario.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Tabla de inventario por técnico (mínima para los smokes)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='inv_tecnico'
  ) THEN
    CREATE TABLE inv_tecnico (
      id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      tecnico_id   UUID NOT NULL,
      material_id  INTEGER NOT NULL,
      cantidad     NUMERIC(12,3) NOT NULL DEFAULT 0,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at   TIMESTAMPTZ
    );

    -- Si tenés tablas tecnicos/materiales con PKs distintas, ajustá estos FKs:
    ALTER TABLE inv_tecnico
      ADD CONSTRAINT fk_inv_tecnico_tecnico
        FOREIGN KEY (tecnico_id) REFERENCES tecnicos(id) ON DELETE CASCADE,
      ADD CONSTRAINT fk_inv_tecnico_material
        FOREIGN KEY (material_id) REFERENCES materiales(id) ON DELETE RESTRICT;

    -- Un técnico no debería tener más de un registro por material
    CREATE UNIQUE INDEX ux_inv_tecnico_tecnico_material
      ON inv_tecnico(tecnico_id, material_id);

    -- Índices de apoyo
    CREATE INDEX ix_inv_tecnico_tecnico ON inv_tecnico(tecnico_id);
    CREATE INDEX ix_inv_tecnico_material ON inv_tecnico(material_id);
  END IF;
END
$$;
