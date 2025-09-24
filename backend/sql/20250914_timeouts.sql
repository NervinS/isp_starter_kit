-- Fija timeouts seguros para evitar “pegadas” por locks o transacciones largas.
-- Ejecuta una sola vez por ambiente.

ALTER DATABASE ispdb SET lock_timeout = '3s';
ALTER DATABASE ispdb SET statement_timeout = '15s';
ALTER DATABASE ispdb SET idle_in_transaction_session_timeout = '10s';

-- Por si manejas credenciales por rol:
ALTER ROLE ispuser SET lock_timeout = '3s';
ALTER ROLE ispuser SET statement_timeout = '15s';
ALTER ROLE ispuser SET idle_in_transaction_session_timeout = '10s';

