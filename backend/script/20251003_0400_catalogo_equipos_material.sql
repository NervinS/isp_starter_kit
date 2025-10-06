-- script/20251003_0400_catalogo_equipos_material.sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_name='catalogo_equipos_material') THEN
    CREATE TABLE catalogo_equipos_material (
      equipo_tipo TEXT PRIMARY KEY CHECK (equipo_tipo IN ('ONT','REPEATER')),
      material_id INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS ix_cat_eq_mat_material ON catalogo_equipos_material(material_id);
  END IF;
END$$;
