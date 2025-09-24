-- 010_cierres_idempotencia.sql
-- Registro para idempotencia de cierres (lado DB, la lógica API la activarás cuando quieras)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS orden_cierres_idem (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_codigo  text        NOT NULL,
  idem_key      text        NOT NULL DEFAULT '',
  payload_hash  text        NOT NULL DEFAULT '',
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now()
);

-- Unicidad por (orden + clave idem + hash del body)
CREATE UNIQUE INDEX IF NOT EXISTS ux_oci_orden_idem_payload
  ON orden_cierres_idem (orden_codigo, idem_key, payload_hash);
