#!/usr/bin/env bash
# script/diagnostico.sh
# Rayos-X del proyecto ISP Starter Kit (infra, API, DB, archivos)
# Salida: ./diagnostics/diag_${TS}.tar.gz
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
OUT="diagnostics/diag_${TS}"
mkdir -p "${OUT}"

note(){ printf "\n=== %s ===\n" "$*" | tee -a "${OUT}/_INDEX.txt"; }

################################################################################
# 0) Contexto y supuestos
################################################################################
# Ajusta si tus servicios en docker-compose se llaman distinto:
: "${DB_SVC:=db}"
: "${API_SVC:=api}"
: "${MINIO_SVC:=minio}"       # si no existe, se omite
: "${WORKDIR:=/home/yarumo/isp_starter_kit/backend}" # ruta esperada del backend

################################################################################
# 1) Host & repo
################################################################################
note "Host: SO / recursos / git"
{
  echo "# Host"
  uname -a
  lsb_release -a 2>/dev/null || true
  echo; echo "# Recursos"
  df -h
  free -m || true
  echo; echo "# Red"
  ip -brief addr || true
  ss -lntp 2>/dev/null | head -n 50 || true
  echo; echo "# Git"
  git -C "${WORKDIR}" rev-parse --is-inside-work-tree && (
    git -C "${WORKDIR}" status -sb
    git -C "${WORKDIR}" log -n 5 --pretty=format:'%h %ad %an %s' --date=iso
    git -C "${WORKDIR}" diff --stat | tail -n +1 || true
  ) || echo "No es repo git en ${WORKDIR}"
} > "${OUT}/host_repo.txt" 2>&1

################################################################################
# 2) Docker / Compose
################################################################################
note "Docker compose: servicios / estado / logs cortos"
{
  docker compose ps
  echo; echo "# Imagenes locales (top 20 por tamaño)"
  docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | head -n 21
  echo; echo "# Inspect servicios relevantes"
  docker compose config | sed -n '1,200p'
} > "${OUT}/docker_compose.txt" 2>&1

# Logs breves (últimas 200 líneas) de servicios clave
for SVC in "${API_SVC}" "${DB_SVC}" "${MINIO_SVC}"; do
  if docker compose ps -q "${SVC}" >/dev/null 2>&1; then
    docker compose logs --no-color --tail=200 "${SVC}" > "${OUT}/logs_${SVC}.txt" 2>&1 || true
  fi
done

################################################################################
# 3) Árbol de proyecto (sin node_modules/.pnpm/.git para aligerar)
################################################################################
note "Árbol de carpetas backend (profundidad 3)"
(
  cd "${WORKDIR}"
  echo "# Raíz backend: ${WORKDIR}"
  find . -maxdepth 3 -type d \
    ! -path '*/node_modules*' \
    ! -path '*/.pnpm*' \
    ! -path '*/.git*' \
    | sort
  echo; echo "# Archivos clave"
  ls -la . | sed -n '1,200p'
  echo; echo "# scripts/ y sql/"
  ls -la script/ sql/ 2>/dev/null || true
) > "${OUT}/tree_backend.txt" 2>&1

################################################################################
# 4) API: versiones, health y endpoints básicos
################################################################################
note "API: versión Node/Nest, health y endpoints de humo"
{
  echo "# Versiones dentro del contenedor API"
  docker compose exec -T "${API_SVC}" node -v 2>/dev/null || true
  docker compose exec -T "${API_SVC}" npm -v  2>/dev/null || true

  echo; echo "# Health"
  curl -sS "http://localhost:3000/v1/health" || true

  echo; echo "# Catálogos mínimos"
  echo "GET /v1/catalogos/motivos-reagenda"
  curl -sS "http://localhost:3000/v1/catalogos/motivos-reagenda" | head -n 50 || true

  echo; echo "# Verificación rutas técnico (sin credenciales): muestra sólo status HTTP"
  for P in \
    "/v1/tecnicos" \
    "/v1/tecnicos/TEC-0001/pendientes" \
    "/v1/tecnicos/TEC-0001/ordenes/TEST-123/iniciar"; do
      CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:3000${P}" || true)
      printf "%-60s %s\n" "${P}" "${CODE}"
  done
} > "${OUT}/api_check.txt" 2>&1

################################################################################
# 5) Base de datos: esquema, constraints, seeds y contadores
################################################################################
note "DB: esquema, constraints, índices, conteos y muestras"
# Helper para ejecutar SQL dentro del contenedor
psqlc(){ docker compose exec -T "${DB_SVC}" psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 "$@"; }

# 5.1 Metadatos generales
{
  echo "# Version y extensiones"
  psqlc -c "SELECT version();" || true
  psqlc -c "SELECT extname, extversion FROM pg_extension ORDER BY 1;" || true

  echo; echo "# Esquema público: tablas"
  psqlc -c "\dt+ public.*" || true

  echo; echo "# Índices por tabla (top 200)"
  psqlc -c "
    SELECT t.relname AS tabla, i.relname AS indice, pg_size_pretty(pg_relation_size(i.oid)) AS size
    FROM pg_class t
    JOIN pg_index ix ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname='public'
    ORDER BY pg_relation_size(i.oid) DESC
    LIMIT 200;
  " || true

  echo; echo "# Constraints NOT NULL/UNIQUE/CHECK (resumen)"
  psqlc -c "
    SELECT conrelid::regclass AS tabla, conname, contype
    FROM pg_constraint
    WHERE connamespace = 'public'::regnamespace
    ORDER BY conrelid::regclass::text, conname;
  " || true

  echo; echo "# Columnas clave de módulos (ordenes, tecnicos, materiales, inv_tecnico)"
  psqlc -c "
    SELECT table_name, column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name IN
      ('ordenes','tecnicos','materiales','inv_tecnico','ordenes_materiales','orden_cierres_idem')
    ORDER BY table_name, ordinal_position;
  " || true
} > "${OUT}/db_schema.txt" 2>&1

# 5.2 Conteos rápidos y top filas (sin datos sensibles)
{
  echo "# Conteos"
  psqlc -c "
    SELECT 'tecnicos' AS t, count(*) FROM tecnicos UNION ALL
    SELECT 'materiales', count(*) FROM materiales UNION ALL
    SELECT 'ordenes', count(*) FROM ordenes UNION ALL
    SELECT 'ordenes_materiales', count(*) FROM ordenes_materiales UNION ALL
    SELECT 'inv_tecnico', count(*) FROM inv_tecnico UNION ALL
    SELECT 'orden_cierres_idem', count(*) FROM orden_cierres_idem
  " || true

  echo; echo "# Muestras"
  echo "## tecnicos"
  psqlc -c "SELECT id::text, codigo, nombre, activo FROM tecnicos ORDER BY created_at DESC NULLS LAST LIMIT 10;" || true
  echo; echo "## materiales"
  psqlc -c "SELECT id, codigo, nombre, precio FROM materiales ORDER BY id LIMIT 10;" || true
  echo; echo "## ordenes (últimas 15)"
  psqlc -c "SELECT codigo, estado, tecnico_id::text, tipo, agendado_para, turno, updated_at FROM ordenes ORDER BY updated_at DESC NULLS LAST LIMIT 15;" || true
  echo; echo "## inv_tecnico (top 15)"
  psqlc -c "SELECT tecnico_id::text, material_id, cantidad FROM inv_tecnico ORDER BY cantidad DESC NULLS LAST LIMIT 15;" || true
  echo; echo "## orden_cierres_idem (top 15)"
  psqlc -c "SELECT orden_codigo, idem_key, status_http, created_at FROM orden_cierres_idem ORDER BY created_at DESC LIMIT 15;" || true
} > "${OUT}/db_samples.txt" 2>&1

# 5.3 Integridad básica (FKs y duplicados potenciales por código)
{
  echo "# FK rotas (si hay)"
  psqlc -c "
    WITH bad AS (
      SELECT o.codigo, o.tecnico_id
      FROM ordenes o
      LEFT JOIN tecnicos t ON t.id = o.tecnico_id
      WHERE o.tecnico_id IS NOT NULL AND t.id IS NULL
    )
    SELECT * FROM bad LIMIT 50;
  " || true

  echo; echo "# Códigos duplicados (debería estar vacío)"
  psqlc -c "
    SELECT 'ordenes' AS tabla, codigo, COUNT(*) FROM ordenes GROUP BY 1,2 HAVING COUNT(*)>1
    UNION ALL
    SELECT 'materiales', codigo, COUNT(*) FROM materiales GROUP BY 1,2 HAVING COUNT(*)>1
    UNION ALL
    SELECT 'tecnicos', codigo, COUNT(*) FROM tecnicos GROUP BY 1,2 HAVING COUNT(*)>1;
  " || true
} > "${OUT}/db_integrity.txt" 2>&1

################################################################################
# 6) MinIO (si existe)
################################################################################
if docker compose ps -q "${MINIO_SVC}" >/dev/null 2>&1; then
  note "MinIO: info general (sin exponer secretos)"
  {
    echo "# Contenedor y puertos"
    docker compose ps "${MINIO_SVC}"
    echo "# Variables visibles en compose (ocultando credenciales)"
    docker compose config | grep -A2 -i minio || true
    echo "# (Sugerencia) Ejecutar mc alias set y mc ls (requiere credenciales de solo lectura)"
    echo "mc alias set local http://minio:9000 <ACCESS_KEY> <SECRET_KEY>"
    echo "mc ls local"
  } > "${OUT}/minio_info.txt" 2>&1
fi

################################################################################
# 7) Smokes disponibles (estado reciente)
################################################################################
note "Smokes: listado y marcas de tiempo"
{
  ls -la script/*.sh 2>/dev/null || true
  echo; echo "# Últimas ejecuciones visibles en logs del API (si aplica arriba)"
  grep -nE 'Smoke|smoke_|/v1/health' "${OUT}/logs_${API_SVC}.txt" 2>/dev/null || true
} > "${OUT}/smokes.txt" 2>&1

################################################################################
# 8) Paquete final
################################################################################
note "Empaquetando resultados"
tar -czf "${OUT}.tar.gz" -C "$(dirname "${OUT}")" "$(basename "${OUT}")"
echo "Artefacto listo: ${OUT}.tar.gz"
echo "Súbelo o compártelo para diagnóstico rápido."
