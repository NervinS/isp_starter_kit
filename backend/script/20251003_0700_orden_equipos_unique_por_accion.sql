DO $$
BEGIN
  -- Quita el unique actual si existe (orden_id, equipo_tipo, serial)
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'orden_equipos_orden_id_equipo_tipo_serial_key'
      AND conrelid = 'public.orden_equipos'::regclass
  ) THEN
    ALTER TABLE public.orden_equipos
      DROP CONSTRAINT orden_equipos_orden_id_equipo_tipo_serial_key;
  END IF;

  -- Crea un unique que incluye la accion (evita duplicados por misma acción,
  -- pero permite tener ambas: asignar y retirar)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ux_orden_equipo_serial_accion'
      AND conrelid = 'public.orden_equipos'::regclass
  ) THEN
    ALTER TABLE public.orden_equipos
      ADD CONSTRAINT ux_orden_equipo_serial_accion
      UNIQUE (orden_id, equipo_tipo, serial, accion);
  END IF;
END$$;
