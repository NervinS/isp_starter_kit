#!/usr/bin/env bash
# smoke_agenda.sh
# Asignar -> Reagendar -> Cancelar agenda (100% por DB, sin usar :'var' de psql)
# Si más adelante expones endpoints HTTP, puedes probar con: AGENDA_MODE=http ./script/smoke_agenda.sh
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
DB_SVC="${DB_SVC:-db}"
PSQL_USER="${PSQL_USER:-ispuser}"
PSQL_DB="${PSQL_DB:-ispdb}"

psql_db() {
  if docker compose ps -q "$DB_SVC" >/dev/null 2>&1; then
    docker compose exec -T "$DB_SVC" psql -U "$PSQL_USER" -d "$PSQL_DB" -v ON_ERROR_STOP=1 "$@"
  else
    psql -U "$PSQL_USER" -d "$PSQL_DB" -v ON_ERROR_STOP=1 "$@"
  fi
}

echo "[health]"
curl -sS "${API_BASE}/v1/health" || true; echo

# --- setup ---------------------------------------------------------
# Técnico (preferimos TEC-0001, si no, el primero que exista):
TECID="$(psql_db -Atc "select id::text from tecnicos where codigo='TEC-0001' limit 1;" 2>/dev/null || true)"
if [[ -z "${TECID}" ]]; then
  TECID="$(psql_db -Atc "select id::text from tecnicos limit 1;" 2>/dev/null || true)"
fi
: "${TECID:=}"   # puede quedar vacío (no rompemos)

# Tipo válido (evitamos violar ck_ordenes_tipo_dom):
TIPO_OK="$(psql_db -Atc "select tipo from ordenes where tipo is not null limit 1;" 2>/dev/null || true)"
TIPO_OK="${TIPO_OK:-instalacion}"

STAMP="$(date -u +%Y%m%d%H%M%S)"
OID="IDEM-${STAMP}-$RANDOM"

# Asegura extensión
psql_db -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" >/dev/null || true

# Crea orden efímera (si ya existe, ignora)
psql_db <<SQL
INSERT INTO ordenes(codigo, estado, tipo)
VALUES ('$OID','creada','$TIPO_OK')
ON CONFLICT (codigo) DO NOTHING;
SQL

# --- ASIGNAR -------------------------------------------------------
echo "[asignar -> DB]"
psql_db <<SQL
UPDATE ordenes
   SET estado        = 'agendada',
       agendado_para = CURRENT_DATE,
       turno         = 'am',
       agendada_at   = NOW(),
       tecnico_id    = CASE WHEN '$TECID' <> '' THEN '$TECID'::uuid ELSE tecnico_id END
 WHERE codigo = '$OID';
SQL

psql_db -Atc "SELECT codigo||'|'||estado||'|'||COALESCE(agendado_para::text,'')||'|'||
                      COALESCE(turno,'')||'|'||COALESCE(agendada_at::text,'')||'|'||
                      COALESCE(tecnico_id::text,'')
               FROM ordenes WHERE codigo='$OID';"

# --- REAGENDAR -----------------------------------------------------
echo "[reagendar -> DB]"
psql_db <<SQL
UPDATE ordenes
   SET estado        = 'agendada',
       agendado_para = CURRENT_DATE,
       turno         = 'pm',
       agendada_at   = NOW(),
       tecnico_id    = CASE WHEN '$TECID' <> '' THEN '$TECID'::uuid ELSE tecnico_id END
 WHERE codigo = '$OID';
SQL

psql_db -Atc "SELECT codigo||'|'||estado||'|'||COALESCE(agendado_para::text,'')||'|'||
                      COALESCE(turno,'')||'|'||COALESCE(agendada_at::text,'')||'|'||
                      COALESCE(tecnico_id::text,'')
               FROM ordenes WHERE codigo='$OID';"

# --- CANCELAR AGENDA ----------------------------------------------
echo "[cancelar agenda -> DB]"
psql_db <<SQL
UPDATE ordenes
   SET agendado_para = NULL,
       turno         = NULL,
       agendada_at   = NULL
 WHERE codigo = '$OID';
SQL

psql_db -Atc "SELECT codigo||'|'||estado||'|'||COALESCE(agendado_para::text,'')||'|'||
                      COALESCE(turno,'')||'|'||COALESCE(agendada_at::text,'')||'|'||
                      COALESCE(tecnico_id::text,'')
               FROM ordenes WHERE codigo='$OID';"

echo "✓ smoke_agenda (DB) OK  (orden=${OID})"

# --- HTTP opcional (no bloquea el smoke) --------------------------
if [[ "${AGENDA_MODE:-db}" == "http" ]]; then
  echo "[HTTP] pruebas informativas de agenda (si aún no expones endpoints, darán 404)"
  AUTH_HEADER=""  # Si tienes token: AUTH_HEADER="Authorization: Bearer <TOKEN>"

  try_http() {
    local method="$1" url="$2" body="$3" label="$4"
    echo "[$label]"
    if [[ -n "$body" ]]; then
      curl -sS -X "$method" -H 'Content-Type: application/json' ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        -d "$body" "$url" || true
    else
      curl -sS -X "$method" ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$url" || true
    fi
    echo; echo
  }

  BODY="$(jq -nc --arg tec "${TECID}" --arg f "$(date +%F)" '{tecnicoId:$tec, fecha:$f, turno:"am"}')"
  try_http POST  "${API_BASE}/v1/agenda/ordenes"                        "$(jq -nc --arg c "${OID}" --arg tec "${TECID}" --arg f "$(date +%F)" '{codigo:$c, tecnicoId:$tec, fecha:$f, turno:"am"}')" "POST /v1/agenda/ordenes"
  try_http PATCH "${API_BASE}/v1/agenda/ordenes/${OID}"                 "$BODY" "PATCH /v1/agenda/ordenes/:codigo"
  try_http POST  "${API_BASE}/v1/ordenes/${OID}/agenda"                 "$BODY" "POST /v1/ordenes/:codigo/agenda"
  try_http PATCH "${API_BASE}/v1/ordenes/${OID}/agenda"                 "$BODY" "PATCH /v1/ordenes/:codigo/agenda"
  try_http POST  "${API_BASE}/v1/ordenes/${OID}/agenda/asignar"         "$BODY" "POST /v1/ordenes/:codigo/agenda/asignar"
  try_http PATCH "${API_BASE}/v1/ordenes/${OID}/estado"                 "$(jq -nc --arg tec "${TECID}" --arg f "$(date +%F)" '{estado:"agendada", tecnicoId:$tec, fecha:$f, turno:"am"}')" "PATCH /v1/ordenes/:codigo/estado"
  echo "ℹ️  HTTP solo informativo; el OK del smoke depende del bloque DB."
fi
