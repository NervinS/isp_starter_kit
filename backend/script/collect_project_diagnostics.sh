#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-project_diagnostics_$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT_DIR"

log(){ printf "== %s ==\n" "$1" | tee -a "$OUT_DIR/00_index.txt"; }

log "Repo & árbol"
{
  echo "# git remotes"
  git remote -v || true
  echo
  echo "# git status"
  git status -s || true
  echo
  echo "# últimas 30 commits"
  git log --oneline -n 30 || true
  echo
  echo "# árbol (hasta 4 niveles, sin .git ni node_modules)"
  if command -v tree >/dev/null 2>&1; then
    tree -a -I '.git|node_modules|dist' -L 4
  else
    find . -maxdepth 4 -not -path './.git/*' -not -path './node_modules/*'
  fi
} > "$OUT_DIR/01_repo.txt" 2>&1

log "Docker"
{
  docker compose ps || true
  echo
  echo "# imágenes"
  docker images | grep -E 'postgres|minio|node|isp' || true
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

log "Entorno y .env"
{
  printenv | sort | sed -n '1,200p'
  echo
  echo "# backend/.env.example"
  sed -n '1,200p' backend/.env.example 2>/dev/null || true
  echo
  echo "# backend/.env"
  sed -n '1,200p' backend/.env 2>/dev/null || true
} > "$OUT_DIR/03_env.txt" 2>&1

log "Base de datos – catálogo y tamaños"
export PGPASSWORD="$(docker compose exec -T db printenv POSTGRES_PASSWORD)"
PSQL="psql -h 127.0.0.1 -p 5433 -U ispuser -d ispdb -v ON_ERROR_STOP=1"
{
  echo "# versión"
  $PSQL -c "SELECT version();"
  echo
  echo "# extensiones"
  $PSQL -c "\\dx"
  echo
  echo "# tamaño BD"
  $PSQL -c "SELECT pg_size_pretty(pg_database_size('ispdb')) AS db_size;"
  echo
  echo "# esquemas"
  $PSQL -c "\\dn+"
  echo
  echo "# tablas"
  $PSQL -c "\\dt+ public.*"
  echo
  echo "# vistas"
  $PSQL -c "\\dv+ public.*"
  echo
  echo "# funciones"
  $PSQL -c "\\df+ public.*"
  echo
  echo "# triggers"
  $PSQL -c "SELECT tgname, tgrelid::regclass, tgtype FROM pg_trigger WHERE NOT tgisinternal;"
  echo
  echo "# constraints"
  $PSQL -c "SELECT conname, contype, conrelid::regclass FROM pg_constraint WHERE connamespace='public'::regnamespace;"
  echo
  echo "# índices"
  $PSQL -c "\\di+ public.*"
  echo
  echo "# definiciones específicas"
  $PSQL -c "\\d+ public.kardex"
  $PSQL -c "\\dS+ public.movimientos"
  $PSQL -c "SELECT * FROM pg_rules WHERE schemaname='public' AND tablename='kardex';"
  echo
  echo "# conteos"
  $PSQL -c "SELECT COUNT(*) AS movimientos FROM public.movimientos;"
  $PSQL -c "SELECT COUNT(*) AS stock_rows FROM public.inventario_tecnico_stock;"
  echo
  echo "# tamaños por tabla"
  $PSQL -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
} > "$OUT_DIR/04_db_catalog.txt" 2>&1

log "Dumps rápidos (schema + seeds)"
{
  pg_dump -h 127.0.0.1 -p 5433 -U ispuser -d ispdb --schema-only > "$OUT_DIR/db_schema.sql"
  pg_dump -h 127.0.0.1 -p 5433 -U ispuser -d ispdb --data-only --inserts --rows-per-insert=100 \
    --table=public.materiales --table=public.tecnicos --table=public.inventario_tecnico_stock > "$OUT_DIR/db_seed.sql"
  echo "Archivos:  db_schema.sql, db_seed.sql"
} > "$OUT_DIR/05_db_dumps.txt" 2>&1 || true

log "API – endpoints clave"
{
  curl -s http://localhost:3000/v1/health || true
  echo
  curl -s http://localhost:3000/v1/inventario/kardex | jq '.[:5]' 2>/dev/null || true
} > "$OUT_DIR/06_api.txt" 2>&1

# Paquete comprimido
tar czf "${OUT_DIR}.tar.gz" "$OUT_DIR"
echo "👉 Paquete listo: ${OUT_DIR}.tar.gz"
