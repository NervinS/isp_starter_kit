#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-project_diagnostics_$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT_DIR"

log(){ printf "== %s ==\n" "$1" | tee -a "$OUT_DIR/00_index.txt"; }

############################################
# 01) Repo & árbol
############################################
log "Repo & árbol"
{
  echo "# git remotes"
  git remote -v || true
  echo
  echo "# git status"
  git status -s || true
  echo
  echo "# últimas 50 commits"
  git log --oneline -n 50 || true
  echo
  echo "# ramas locales"
  git branch -vv || true
  echo
  echo "# tags"
  git tag -l || true
  echo
  echo "# árbol (hasta 4 niveles, sin .git ni node_modules ni dist)"
  if command -v tree >/dev/null 2>&1; then
    tree -a -I '.git|node_modules|dist' -L 4
  else
    find . -maxdepth 4 -not -path './.git/*' -not -path './node_modules/*' -not -path './dist/*'
  fi
} > "$OUT_DIR/01_repo.txt" 2>&1

############################################
# 02) Docker / Contenedores
############################################
log "Docker"
{
  echo "# compose ps"
  docker compose ps || true
  echo
  echo "# imágenes relevantes"
  docker images | grep -E 'postgres|minio|node|isp' || true
  echo
  echo "# docker-compose.yml"
  sed -n '1,400p' docker-compose.yml 2>/dev/null || true
  echo
  echo "# docker-compose.override.yml"
  sed -n '1,400p' docker-compose.override.yml 2>/dev/null || true
  echo
  echo "# logs api (últ. 400 líneas)"
  docker compose logs --no-color --tail=400 api || true
  echo
  echo "# logs db (últ. 200 líneas)"
  docker compose logs --no-color --tail=200 db || true
  echo
  echo "# logs minio (últ. 200 líneas)"
  docker compose logs --no-color --tail=200 minio || true
} > "$OUT_DIR/02_docker.txt" 2>&1

############################################
# 03) Entorno y variables
############################################
log "Entorno y .env"
{
  echo "# printenv (ordenado)"
  printenv | sort | sed -n '1,400p'
  echo
  echo "# backend/.env.example (si existe)"
  sed -n '1,400p' backend/.env.example 2>/dev/null || true
  echo
  echo "# backend/.env (si existe)"
  sed -n '1,400p' backend/.env 2>/dev/null || true
} > "$OUT_DIR/03_env.txt" 2>&1

############################################
# 04) Backend – archivos clave
############################################
log "Backend – archivos clave"
{
  echo "## package.json"
  sed -n '1,400p' package.json 2>/dev/null || true
  echo
  echo "## tsconfig.json"
  sed -n '1,400p' tsconfig.json 2>/dev/null || true
  echo
  echo "## tsconfig.build.json"
  sed -n '1,400p' tsconfig.build.json 2>/dev/null || true
  echo
  echo "## src/main.ts"
  sed -n '1,300p' src/main.ts 2>/dev/null || true
  echo
  echo "## Guards"
  sed -n '1,300p' src/common/guards/api-key.guard.ts 2>/dev/null || true
  sed -n '1,300p' src/common/guards/tech-smoke-bypass.guard.ts 2>/dev/null || true
  echo
  echo "## Interceptors & Middlewares"
  sed -n '1,300p' src/common/interceptors/reqid-logger.interceptor.ts 2>/dev/null || true
  sed -n '1,300p' src/common/middleware/request-id.middleware.ts 2>/dev/null || true
  sed -n '1,300p' src/common/middleware/logger.middleware.ts 2>/dev/null || true
  echo
  echo "## Módulos cargados en AppModule"
  sed -n '1,300p' src/app.module.ts 2>/dev/null || true
  echo
  echo "## Health"
  sed -n '1,200p' src/modules/health/health.controller.ts 2>/dev/null || true
  sed -n '1,200p' dist/modules/health/health.controller.js 2>/dev/null || true
  echo
  echo "## Inventario – DTOs y service"
  sed -n '1,300p' src/modules/inventario/dto/tecnico-mov.dto.ts 2>/dev/null || true
  sed -n '1,400p' src/modules/inventario/inventario.service.ts 2>/dev/null || true
  echo
  echo "## Órdenes – controller/service (si existen)"
  sed -n '1,400p' src/modules/ordenes/ordenes.controller.ts 2>/dev/null || true
  sed -n '1,400p' src/modules/ordenes/ordenes.service.ts 2>/dev/null || true
  echo
  echo "## Ventas – controller/service (si existen)"
  sed -n '1,400p' src/modules/ventas/ventas.controller.ts 2>/dev/null || true
  sed -n '1,400p' src/modules/ventas/ventas.service.ts 2>/dev/null || true
  echo
  echo "## PDFs / MinIO (si aplica)"
  sed -n '1,400p' src/modules/pdf/pdf.service.ts 2>/dev/null || true
  sed -n '1,400p' src/modules/minio/minio.service.ts 2>/dev/null || true
} > "$OUT_DIR/04_backend.txt" 2>&1

############################################
# 05) Base de datos – catálogo y tamaños
############################################
log "Base de datos – catálogo y tamaños"
{
  echo "# versión"
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT version();" || true
  echo
  echo "# extensiones"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\dx" || true
  echo
  echo "# tamaño BD"
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT pg_size_pretty(pg_database_size('ispdb')) AS db_size;" || true
  echo
  echo "# esquemas"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\dn+" || true
  echo
  echo "# tablas"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\dt+ public.*" || true
  echo
  echo "# vistas"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\dv+ public.*" || true
  echo
  echo "# funciones"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\df+ public.*" || true
  echo
  echo "# triggers (no internos)"
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT tgname, tgrelid::regclass, tgtype FROM pg_trigger WHERE NOT tgisinternal;" || true
  echo
  echo "# constraints"
  docker compose exec -T db psql -U ispuser -d ispdb -c \"SELECT conname, contype, conrelid::regclass FROM pg_constraint WHERE connamespace='public'::regnamespace;\" || true
  echo
  echo "# índices"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\di+ public.*" || true
  echo
  echo "# definiciones específicas (kardex y movimientos)"
  docker compose exec -T db psql -U ispuser -d ispdb -c "\d+ public.movimientos" || true
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT pg_get_viewdef('public.v_kardex_det'::regclass, true) AS viewdef;" || true
  echo
  echo "# conteos críticos"
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT COUNT(*) AS movimientos FROM public.movimientos;" || true
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT COUNT(*) AS stock_rows FROM public.inventario_tecnico_stock;" || true
  echo
  echo "# tamaños por tabla"
  docker compose exec -T db psql -U ispuser -d ispdb -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;" || true
} > "$OUT_DIR/05_db_catalog.txt" 2>&1

############################################
# 06) DB dumps (schema + seeds mínimas)
############################################
log "Dumps rápidos (schema + seeds)"
{
  docker compose exec -T db pg_dump -U ispuser -d ispdb --schema-only > "$OUT_DIR/db_schema.sql"
  docker compose exec -T db pg_dump -U ispuser -d ispdb --data-only --inserts --rows-per-insert=100 \
    --table=public.materiales \
    --table=public.tecnicos \
    --table=public.inventario_tecnico_stock \
    > "$OUT_DIR/db_seed.sql"
  echo "Archivos:  db_schema.sql, db_seed.sql"
} > "$OUT_DIR/06_db_dumps.txt" 2>&1 || true

############################################
# 07) API – smoke con API key si está disponible
############################################
log "API – endpoints clave"
{
  API_BASE="${API_BASE:-http://localhost:3000/v1}"
  API_KEY_HDR=()
  if [ -n "${API_KEY:-}" ]; then
    API_KEY_HDR=(-H "x-api-key: ${API_KEY}")
  fi
  echo "# /health"
  curl -s "${API_KEY_HDR[@]}" "${API_BASE}/health" || true
  echo
  echo "# /inventario/kardex (top 5)"
  if [ -n "${API_KEY:-}" ]; then
    curl -s "${API_BASE}/inventario/kardex?api_key=${API_KEY}" | jq '.[:5]' 2>/dev/null || true
  else
    curl -s "${API_BASE}/inventario/kardex" | jq '.[:5]' 2>/dev/null || true
  fi
} > "$OUT_DIR/07_api.txt" 2>&1

############################################
# 08) Tests – listado y últimos resultados
############################################
log "Tests – listado y últimos resultados"
{
  echo "# jest-e2e.json (si existe)"
  sed -n '1,300p' test/jest-e2e.json 2>/dev/null || true
  echo
  echo "# suites"
  ls -la test 2>/dev/null || true
  ls -la test/e2e 2>/dev/null || true
  echo
  echo "# specs (extractos)"
  sed -n '1,250p' test/e2e/health.e2e-spec.ts 2>/dev/null || true
  sed -n '1,250p' test/inventario.e2e-spec.ts 2>/dev/null || true
  sed -n '1,250p' test/e2e/cerrar.e2e-spec.ts 2>/dev/null || true
} > "$OUT_DIR/08_tests.txt" 2>&1

############################################
# 09) MinIO – configuración efectiva (si es visible)
############################################
log "MinIO – variables relevantes"
{
  echo "# Variables a revisar para NAT / URLs firmadas"
  env | grep -E 'MINIO|PDF_FORCE_PUBLIC_URL|BUCKET|PUBLIC_BASE|EXTERNAL_URL' | sort || true
  echo
  echo "# Nota: este script no usa mc; validar manualmente accesos si es necesario."
} > "$OUT_DIR/09_minio.txt" 2>&1

############################################
# 10) Resumen operativo y próximos pasos
############################################
log "Resumen operativo y próximos pasos"
{
  cat <<'TXT'
== Estado actual ==
- Guard de API key activo (si API_KEY está definido)
- Interceptor de request-id y logs [REQ]/[RES]
- /v1/health con dbOk/dbTime (consulta real a Postgres)
- Inventario técnico estable, kardex con vista v_kardex_det
- Órdenes: cierre idempotente con descuento de stock por líneas
- Ventas: crear/pagar → orden de instalación + PDFs
- Docker compose y override funcionales

== Pendientes recomendados ==
1) DB: columnas payload/evidencias/tipo en ordenes + tabla orden_equipos (serializados)
2) Controlador de Órdenes: crear/asignar/evidencias/guardar/cerrar por tipo (MAN,COR,REC,BAJ,TRA,CMB,RCT)
3) Jobs COR/REC/BAJ (cron/manual) + transición de estado de usuario
4) Usuarios: estados y endpoints internos
5) PDFs por tipo de orden
6) Front técnico /tecnico/{COD} con formularios y stock lateral
7) E2E por caso de negocio + smokes de jobs
TXT
} > "$OUT_DIR/10_summary.txt" 2>&1

############################################
# 11) Paquete comprimido
############################################
tar czf "${OUT_DIR}.tar.gz" "$OUT_DIR"
echo "👉 Paquete listo: ${OUT_DIR}.tar.gz"
