-- 20251003_0100_fk_ordenes_usuarios.sql
DO $$
BEGIN
  -- Columna ya existe según tu entity: usuario_id (uuid, nullable)
  -- Creamos índice y FK con ON DELETE SET NULL para no romper histórico.
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'ix_ordenes_usuario'
  ) THEN
    EXECUTE 'CREATE INDEX ix_ordenes_usuario ON ordenes(usuario_id)';
  END IF;

  -- Intenta crear la FK si no existe
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_ordenes_usuarios'
  ) THEN
    EXECUTE 'ALTER TABLE ordenes
      ADD CONSTRAINT fk_ordenes_usuarios
      FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
      ON DELETE SET NULL';
  END IF;
END$$;

