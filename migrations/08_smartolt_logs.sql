
CREATE TABLE smartolt_logs(
  id uuid primary key default gen_random_uuid(),
  endpoint text not null,
  metodo text not null,
  request_id uuid not null,
  timestamp timestamptz not null default now(),
  payload_redacted jsonb,
  status_code int,
  response_trunc jsonb,
  error_text text,
  retry_count int default 0,
  correlacion text
);
CREATE INDEX idx_smartolt_request ON smartolt_logs(request_id);
