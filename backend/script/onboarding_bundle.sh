#!/usr/bin/env bash
# script/onboarding_bundle.sh
# Paquete de onboarding para ingeniero senior: snapshot de infra+API+DB+operación
# Salida: ./onboarding/onboard_${TS}.tar.gz + RUNBOOK.md con instrucciones vivas
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# 0) Contexto y variables (ajusta si tus servicios tienen otros nombres)
# ──────────────────────────────────────────────────────────────────────────────
: "${DB_SVC:=db}"
: "${API_SVC:=api}"
: "${MINIO_SVC:=minio}"   # si no existe, se ignora
: "${WORKDIR:=$(pwd)}"
: "${API_BASE:=http://localhost:3000}"

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="onboarding/onboard_${TS}"
RUNBOOK="${OUT_DIR}/RUNBOOK.md"
mkdir -p "${OUT_DIR}"

log(){ printf "\n[onboard] %s\n" "$*"; }
redact(){ sed -E 's#(SECRET|TOKEN|KEY|PASSWORD|PASS|ACCESS|JWT|MINIO_.+KEY)(=|:)\s*[^[:space:]]+#\1\2 ********#Ig'; }
dc(){ docker compose "$@"; }
psqlc(){ dc exec -T "${DB_SVC}" psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 "$@"; }

# ──────────────────────────────────────────────────────────────────────────────
# 1) Snapshot de host + repo + docker (similar al “rayos-X”, pero con foco onboarding)
# ──────────────────────────────────────────────────────────────────────────────
log "Snapshot de host, git y compose"
{
  echo "## Host"
  uname -a
  lsb_release -a 2>/dev/null || true
  echo; echo "## Recursos"; df -h; free -m || true

  echo; echo "## Git (últimos commits + estado)"
  if git -C "${WORKDIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "\$ git status -sb"; git -C "${WORKDIR}" status -sb
    echo; echo "\$ git log -n 10"; git -C "${WORKDIR}" log -n 10 --pretty=format:'%h %ad %an %s' --date=iso
  else
    echo "No es repo git: ${WORKDIR}"
  fi

  echo; echo "## Compose ps"
  dc ps

  echo; echo "## Compose config (primeros 300 líneas, sin secretos)"
  dc config | head -n 300 | redact
} > "${OUT_DIR}/00_host_repo_compose.txt" 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# 2) Entornos y configuración (redactado seguro)
# ──────────────────────────────────────────────────────────────────────────────
log "Copiando configuración y .env (redactado)"
{
  # Archivos típicos de configuración
  for f in .env .env.local .env.production .env.development package.json pnpm-lock.yaml yarn.lock docker-compose.yml; do
    [ -f "${f}" ] && { echo "### ${f}"; echo; cat "${f}" | redact; echo; }
  done
} > "${OUT_DIR}/01_env_y_config.txt" 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# 3) API: salud, versiones, Swagger (si existe), endpoints clave
# ──────────────────────────────────────────────────────────────────────────────
log "Chequeos de API + intento de export Swagger"
{
  echo "# Versiones en contenedor API"
  dc exec -T "${API_SVC}" node -v 2>/dev/null || true
  dc exec -T "${API_SVC}" npm -v  2>/dev/null || true

  echo; echo "# Health"
  curl -sS "${API_BASE}/v1/health" || true

  echo; echo "# Endpoints de referencia (sin auth, solo HTTP code)"
  for P in \
    /v1/catalogos/motivos-reagenda \
    /v1/catalogos/motivos_reagenda/items?soloActivos=true \
    /v1/ventas \
    /v1/tecnicos \
    /v1/ordenes/ORD-XXXX/estado \
    /v1/tecnicos/TEC-0001/pendientes; do
      CODE=$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE}${P}" || true)
      printf "%-60s %s\n" "${P}" "${CODE}"
  done
} > "${OUT_DIR}/02_api_health_endpoints.txt" 2>&1

# Swagger JSON (si está publicado; común en Nest: /docs-json o /v1/docs-json)
for SW in "/docs-json" "/v1/docs-json" "/swagger-json" ; do
  if curl -fsS "${API_BASE}${SW}" -o "${OUT_DIR}/swagger.json" 2>/dev/null; then
    log "Swagger exportado desde ${SW}"
    break
  fi
done || true

# ──────────────────────────────────────────────────────────────────────────────
# 4) DB: esquema, constraints, seeds visibles, dumps CSV ligeros (top-N)
# ──────────────────────────────────────────────────────────────────────────────
log "Extrayendo esquema y muestras de BD"
{
  echo "# Version / Extensiones"
  psqlc -c "SELECT version();" || true
  psqlc -c "SELECT extname, extversion FROM pg_extension ORDER BY 1;" || true

  echo; echo "# Tablas"
  psqlc -c "\dt+ public.*" || true

  echo; echo "# Columnas de tablas núcleo"
  psqlc -c "
    SELECT table_name, column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name IN ('tecnicos','materiales','ordenes','ordenes_materiales','inv_tecnico','orden_cierres_idem','ventas')
    ORDER BY table_name, ordinal_position;
  " || true

  echo; echo "# Constraints clave"
  psqlc -c "
    SELECT conrelid::regclass AS tabla, conname, contype
    FROM pg_constraint
    WHERE connamespace='public'::regnamespace
    ORDER BY 1,2;
  " || true
} > "${OUT_DIR}/03_db_schema.txt" 2>&1

# CSVs ligeros (para entender forma y datos base sin PII)
log "Exportando CSVs ligeros"
CSV_OUT="${OUT_DIR}/csv"
mkdir -p "${CSV_OUT}"
export_csv(){ local sql="$1" out="$2"; psqlc -A -F, -q -c "\COPY ($sql) TO STDOUT CSV HEADER" > "${CSV_OUT}/${out}" || true; }

export_csv "SELECT id::text,codigo,nombre,activo,created_at FROM tecnicos ORDER BY created_at DESC NULLS LAST LIMIT 50" "tecnicos.csv"
export_csv "SELECT id,codigo,nombre,precio FROM materiales ORDER BY id LIMIT 200" "materiales.csv"
export_csv "SELECT codigo,estado,tipo,tecnico_id::text,agendado_para,turno,updated_at FROM ordenes ORDER BY updated_at DESC NULLS LAST LIMIT 200" "ordenes.csv"
export_csv "SELECT orden_id::text,material_id,cantidad,precio_unitario FROM ordenes_materiales ORDER BY orden_id LIMIT 500" "ordenes_materiales.csv"
export_csv "SELECT tecnico_id::text,material_id,cantidad FROM inv_tecnico ORDER BY cantidad DESC NULLS LAST LIMIT 500" "inv_tecnico.csv"
export_csv "SELECT orden_codigo,idem_key,status_http,created_at FROM orden_cierres_idem ORDER BY created_at DESC LIMIT 500" "orden_cierres_idem.csv"
export_csv "SELECT codigo, estado, total, mensual_total, created_at FROM ventas ORDER BY created_at DESC LIMIT 200" "ventas.csv"

# ──────────────────────────────────────────────────────────────────────────────
# 5) Logs operativos recientes (API/DB/MINIO)
# ──────────────────────────────────────────────────────────────────────────────
log "Recolectando logs cortos"
for SVC in "${API_SVC}" "${DB_SVC}" "${MINIO_SVC}"; do
  if dc ps -q "${SVC}" >/dev/null 2>&1; then
    dc logs --no-color --tail=300 "${SVC}" > "${OUT_DIR}/log_${SVC}.txt" 2>&1 || true
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# 6) Inventario de scripts de operación (smokes, stress, migraciones)
# ──────────────────────────────────────────────────────────────────────────────
log "Inventariando scripts (script/*.sh) y SQL (sql/*.sql)"
{
  echo "# scripts/"
  ls -la script 2>/dev/null || true
  echo; echo "# sql/"
  ls -la sql 2>/dev/null || true
} > "${OUT_DIR}/04_scripts_sql_inventory.txt" 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# 7) Generar RUNBOOK.md con guía viva de operación
# ──────────────────────────────────────────────────────────────────────────────
log "Generando RUNBOOK.md"
cat > "${RUNBOOK}" <<'MD'
# RUNBOOK — ISP Starter Kit (Backend)
> Paquete de onboarding para ingeniería. Este documento se genera automáticamente por `script/onboarding_bundle.sh`.

## 1. Arquitectura (alto nivel)
- **API (NestJS)** expone `/v1/*` para catálogos, ventas, agenda/técnicos e inventario.
- **DB (PostgreSQL)** con tablas núcleo: `tecnicos`, `materiales`, `ordenes`, `ordenes_materiales`, `inv_tecnico`, `ventas`, `orden_cierres_idem`.
- **MinIO** para evidencias (cedula/recibo/firma) y PDFs (recibo/contrato).
- **Front** (Next.js) consume API vía proxy `/api/*`.

## 2. Levantar entorno local
```bash
docker compose up -d           # api, db, (minio si aplica)
docker compose ps
curl -s http://localhost:3000/v1/health
