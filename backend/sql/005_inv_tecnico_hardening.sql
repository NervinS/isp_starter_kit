-- sql/005_inv_tecnico_hardening.sql
-- Endurecimiento de la tabla de inventario (inv_tecnico)

DO $$
BEGIN
  -- FK a tecnicos(id)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_inv_tecnico_tecnico'
  ) THEN
    ALTER TABLE public.inv_tecnico
      ADD CONSTRAINT fk_inv_tecnico_tecnico
      FOREIGN KEY (tecnico_id) REFERENCES public.tecnicos(id)
      ON UPDATE CASCADE ON DELETE CASCADE;
  END IF;

  -- FK a materiales(id)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_inv_tecnico_material'
  ) THEN
    ALTER TABLE public.inv_tecnico
      ADD CONSTRAINT fk_inv_tecnico_material
      FOREIGN KEY (material_id) REFERENCES public.materiales(id)
      ON UPDATE CASCADE ON DELETE RESTRICT;
  END IF;

  -- CHECK cantidad >= 0 (idempotente)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_inv_tecnico_cantidad_nn'
  ) THEN
    ALTER TABLE public.inv_tecnico
      ADD CONSTRAINT chk_inv_tecnico_cantidad_nn
      CHECK (cantidad >= 0);
  END IF;
END$$;
