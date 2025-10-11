-- backend/script/seed_ci.sql

-- Asegura el técnico TEC-6
INSERT INTO usuarios (id, cliente_codigo, tipo_cliente, email, telefono)
VALUES (gen_random_uuid(), 'TEC-6', 'TECNICO', NULL, NULL)
ON CONFLICT (cliente_codigo) DO NOTHING;

-- Asegura una orden INS agendada para hoy
INSERT INTO ordenes (
  tipo, estado, turno, agendado_para, tecnico_id, created_at, codigo
) VALUES (
  'INS', 'agendada', 'AM', CURRENT_DATE,
  (SELECT id FROM usuarios WHERE cliente_codigo='TEC-6' LIMIT 1),
  now(), 'INS-CI-0001'
)
ON CONFLICT DO NOTHING;
