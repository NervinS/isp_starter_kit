#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config
# =========================
OUT_DIR="${OUT_DIR:-project_diagnostics_$(date -u +%Y%m%dT%H%M%SZ)}"
API_BASE_RAW="${API_BASE_RAW:-http://localhost:3000}"   # sin /v1
API_BASE_V1="${API_BASE_V1:-${API_BASE_RAW%/}/v1}"      # con /v1
API_KEY="${API_KEY:-}"                                  # x-api-key (opcional)
DB_SVC="${DB_SVC:-db}"                                  # nombre del servicio en docker compose
DB_USER="${DB_USER:-ispuser}"
DB_NAME="${DB_NAME:-ispdb}"
MINIO_PUBLIC_BASE="${MINIO_PUBLIC_BASE:-http://127.0.0.1:9000}"

mkdir -p "$OUT_DIR"

log(){ printf "== %s ==\n" "$1" | tee -a "$OUT_DIR/00_index.txt"; }

hdr_api=()
[[ -n "$API_KEY" ]] && hdr_api=(-H "x-api-key: ${API_KEY}" -H "content-type: application/json")

# Util: ejecutar psql dentro del contenedor
psqlc(){ docker compose exec -T "$DB_SVC" psql -U "$DB_USER" -d "$DB_NAME" "$@"; }

# =========================
# 01) Repo & árbol
# =========================
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
    tree -a -I '.git|node_modules|dist|.next|out' -L 4
  else
    find . -maxdepth 4 -not -path './.git/*' -not -path './node_modules/*' -not -path './dist/*' -not -path './.next/*' -not -path './out/*'
  fi
} > "$OUT_DIR/01_repo.txt" 2>&1

# =========================
# 02) Docker / Contenedores
# =========================
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
  docker compose logs --no-color --tail=200 "$DB_SVC" || true
  echo
  echo "# logs minio (últ. 200 líneas)"
  docker compose logs --no-color --tail=200 minio || true
} > "$OUT_DIR/02_docker.txt" 2>&1

# =========================
# 03) Entorno y variables
# =========================
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

# =========================
# 04) Backend – archivos clave
# =========================
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
  sed -n '1,400p' src/modules/inventario/dto/tecnico-mov.dto.ts 2>/dev/null || true
  sed -n '1,500p' src/modules/inventario/inventario.service.ts 2>/dev/null || true
  echo
  echo "## Órdenes – controller/service (si existen)"
  sed -n '1,500p' src/modules/ordenes/ordenes.controller.ts 2>/dev/null || true
  sed -n '1,500p' src/modules/ordenes/ordenes.service.ts 2>/dev/null || true
  echo
  echo "## Ventas – controller/service (si existen)"
  sed -n '1,500p' src/modules/ventas/ventas.controller.ts 2>/dev/null || true
  sed -n '1,500p' src/modules/ventas/ventas.service.ts 2>/dev/null || true
  echo
  echo "## PDFs / MinIO (si aplica)"
  sed -n '1,500p' src/modules/pdf/pdf.service.ts 2>/dev/null || true
  sed -n '1,500p' src/modules/minio/minio.service.ts 2>/dev/null || true
} > "$OUT_DIR/04_backend.txt" 2>&1

# =========================
# 04b) OpenAPI (swagger)
# =========================
log "OpenAPI (swagger)"
{
  # intentos comunes: /docs-json (Nest Swagger), /swagger-json, /openapi.json
  ok=0
  for url in \
    "${API_BASE_RAW%/}/docs-json" \
    "${API_BASE_RAW%/}/swagger-json" \
    "${API_BASE_V1%/}/docs-json" \
    "${API_BASE_V1%/}/swagger-json" \
    "${API_BASE_RAW%/}/openapi.json" \
    "${API_BASE_V1%/}/openapi.json"
  do
    code=$(curl -s -o "$OUT_DIR/openapi.json" -w '%{http_code}' "${hdr_api[@]}" "$url" || echo 000)
    if [[ "$code" == "200" ]]; then
      echo "OpenAPI desde: $url" > "$OUT_DIR/04b_openapi.txt"
      ok=1; break
    fi
  done
  if [[ "$ok" == "0" ]]; then
    echo "No se pudo extraer OpenAPI automáticamente." > "$OUT_DIR/04b_openapi.txt"
    rm -f "$OUT_DIR/openapi.json" || true
  fi
} >> "$OUT_DIR/04b_openapi.txt" 2>&1

# =========================
# 05) Base de datos – catálogo y tamaños
# =========================
log "Base de datos – catálogo y tamaños"
{
  echo "# versión"
  psqlc -c "SELECT version();"
  echo
  echo "# extensiones"
  psqlc -c "\dx"
  echo
  echo "# tamaño BD"
  psqlc -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;"
  echo
  echo "# esquemas"
  psqlc -c "\dn+"
  echo
  echo "# tablas"
  psqlc -c "\dt+ public.*"
  echo
  echo "# vistas"
  psqlc -c "\dv+ public.*"
  echo
  echo "# funciones"
  psqlc -c "\df+ public.*"
  echo
  echo "# triggers (no internos)"
  psqlc -c "SELECT tgname, tgrelid::regclass, tgtype FROM pg_trigger WHERE NOT tgisinternal;"
  echo
  echo "# constraints"
  psqlc -c "SELECT conname, contype, conrelid::regclass FROM pg_constraint WHERE connamespace='public'::regnamespace;"
  echo
  echo "# índices"
  psqlc -c "\di+ public.*"
  echo
  echo "# definiciones específicas (kardex y movimientos si existen)"
  psqlc -c "\d+ public.movimientos" || true
  psqlc -c "SELECT pg_get_viewdef('public.v_kardex_det'::regclass, true) AS viewdef;" || true
  echo
  echo "# conteos críticos"
  psqlc -c "SELECT COUNT(*) AS movimientos FROM public.movimientos;" || true
  psqlc -c "SELECT COUNT(*) AS stock_rows FROM public.inventario_tecnico_stock;" || true
  echo
  echo "# tamaños por tabla"
  psqlc -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total
            FROM pg_catalog.pg_statio_user_tables
            ORDER BY pg_total_relation_size(relid) DESC;"
} > "$OUT_DIR/05_db_catalog.txt" 2>&1

# =========================
# 06) BD – esquema detallado por tabla + ERD
# =========================
log "BD – esquema detallado por tabla + ERD"
{
  # Lista de tablas
  psqlc -qtA -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;" > "$OUT_DIR/.tables" || true

  # Descripciones detalladas (\d+)
  {
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      echo "### TABLE: public.$t"
      psqlc -c "\d+ public.$t" || true
      echo
    done < "$OUT_DIR/.tables"
  } > "$OUT_DIR/06_schema_tables.txt" 2>&1

  # FK para ERD (DOT)
  psqlc -qtA -F $'\t' -c "
    SELECT
      tc.table_name      AS child_table,
      kcu.column_name    AS child_column,
      ccu.table_name     AS parent_table,
      ccu.column_name    AS parent_column,
      tc.constraint_name AS constraint_name
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
     AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
     AND ccu.table_schema = tc.table_schema
   WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='public';
  " > "$OUT_DIR/.fks.tsv" || true

  {
    echo 'digraph ERD {'
    echo '  graph [rankdir=LR, splines=true, overlap=false];'
    echo '  node  [shape=record, fontname="Helvetica"];'
    # nodos simples por tabla
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      echo "  \"$t\" [label=\"{$t}\"];"
    done < "$OUT_DIR/.tables"
    # aristas por FK
    while IFS=$'\t' read -r child col parent pcol cname; do
      [[ -z "${child:-}" || -z "${parent:-}" ]] && continue
      echo "  \"$child\" -> \"$parent\" [label=\"$col → $pcol\", fontsize=10];"
    done < "$OUT_DIR/.fks.tsv"
    echo '}'
  } > "$OUT_DIR/06_erd.dot"

  if command -v dot >/dev/null 2>&1; then
    dot -Tpng "$OUT_DIR/06_erd.dot" -o "$OUT_DIR/06_erd.png" || true
  fi
} > "$OUT_DIR/06_schema_erd.txt" 2>&1

# =========================
# 07) DB dumps (schema + seeds + muestras)
# =========================
log "Dumps rápidos (schema + seeds + muestras)"
{
  docker compose exec -T "$DB_SVC" pg_dump -U "$DB_USER" -d "$DB_NAME" --schema-only > "$OUT_DIR/db_schema.sql"
  docker compose exec -T "$DB_SVC" pg_dump -U "$DB_USER" -d "$DB_NAME" --data-only --inserts --rows-per-insert=100 \
    --table=public.materiales \
    --table=public.tecnicos \
    --table=public.inventario_tecnico_stock \
    --table=public.ordenes 2>/dev/null \
    > "$OUT_DIR/db_seed.sql" || true

  # Muestras de datos (hasta 50 filas por tabla común)
  for T in materiales tecnicos inventario_tecnico_stock ordenes ventas movimientos orden_materiales equipos usuarios; do
    psqlc -c "TABLE public.$T LIMIT 50;" > "$OUT_DIR/sample_${T}.txt" 2>/dev/null || true
  done
  echo "Archivos:  db_schema.sql, db_seed.sql, sample_*.txt"
} > "$OUT_DIR/07_db_dumps.txt" 2>&1

# =========================
# 08) API – endpoints clave
# =========================
log "API – endpoints clave"
{
  echo "# /health (raw)"
  curl -s "${hdr_api[@]}" "${API_BASE_RAW%/}/health" || true
  echo
  echo "# /v1/health"
  curl -s "${hdr_api[@]}" "${API_BASE_V1%/}/health" || true
  echo
  echo "# /inventario/kardex (top 5)"
  curl -s "${hdr_api[@]}" "${API_BASE_V1%/}/inventario/kardex" | jq '.[:5]' 2>/dev/null || curl -s "${hdr_api[@]}" "${API_BASE_V1%/}/inventario/kardex" || true
  echo
  echo "# /ventas (si existe, listar últimas 5)"
  curl -s "${hdr_api[@]}" "${API_BASE_V1%/}/ventas" | jq '.| (.[0:5] // .)' 2>/dev/null || true
  echo
  echo "# /ordenes/INS-000007 (si existe)"
  curl -s "${hdr_api[@]}" "${API_BASE_V1%/}/ordenes/INS-000007" 2>/dev/null || true
} > "$OUT_DIR/08_api.txt" 2>&1

# =========================
# 09) Tests – listado y últimos resultados
# =========================
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
} > "$OUT_DIR/09_tests.txt" 2>&1

# =========================
# 10) MinIO – configuración efectiva
# =========================
log "MinIO – variables relevantes"
{
  echo "# Variables a revisar para NAT / URLs firmadas"
  env | grep -E 'MINIO|PDF_FORCE_PUBLIC_URL|BUCKET|PUBLIC_BASE|EXTERNAL_URL' | sort || true
  echo
  echo "# Public base esperado: ${MINIO_PUBLIC_BASE}"
} > "$OUT_DIR/10_minio.txt" 2>&1

# =========================
# 11) Resumen operativo y próximos pasos
# =========================
log "Resumen operativo y próximos pasos"
{
  cat <<'TXT'
== Estado actual (verificado) ==
- Guard de API key activo (si API_KEY está definido)
- Interceptor de request-id y logs [REQ]/[RES]
- /v1/health con dbOk/dbTime (consulta real a Postgres)
- Inventario técnico estable, kardex con vista v_kardex_det
- Cierre de órdenes idempotente (descuento único por líneas) probado en smokes
- Ventas: crear/pagar → orden de instalación (INS) + PDFs (recibo/contrato)
- MinIO: guardado y firmas de URL funcionando (según configuración)
- Catálogos dirección: municipios/sectores/vías desde BD
- Scripts smoke actualizados y pasando

== Pendientes recomendados ==
1) Idempotencia por API en inventario (usar Idempotency-Key a nivel handler).
2) Módulo Órdenes por tipo (MAN, COR, REC, BAJ, TRA, CMB, RCT):
   - GET /v1/ordenes/:codigo, POST evidencias, POST cerrar {payload por tipo}
   - PDF de cierre con firma/blocks condicionales
3) Jobs administrativos:
   - CORTE auto por impago ⇒ desconectado
   - RECONEXIÓN auto por pago ⇒ instalado
   - BAJA TOTAL auto >30 días impago → agendada
4) Estados de Usuario y hooks en eventos de negocio (pagar INS, COR, REC, BAJ).
5) Almacén principal (ingreso/traslado/devolución) + catálogos de materiales y equipos.
6) Equipos con serial (ONT/Repetidor) con endpoints de disponibilidad y validaciones.
7) Roles simples (ventas/técnico/admin) y middleware de autorización.
8) E2E por caso de negocio + smokes de jobs.
TXT
} > "$OUT_DIR/11_summary.txt" 2>&1

# =========================
# 12) Smokes (opcional)
# =========================
log "Smokes (opcional)"
{
  # Corre algunos smokes si existen (no falla el paquete si faltan)
  try_run() {
    local s="$1"
    if [[ -x "script/$s" ]]; then
      echo ">>> Running script/$s"
      ("script/$s") || echo "WARN: $s exit != 0"
      echo
    fi
  }
  try_run "smoke_inventory.sh"
  try_run "smoke_inventario_min.sh"
  try_run "smoke_kardex_min.sh"
  try_run "smoke_agenda.sh"
  try_run "smoke_agenda_verbose.sh"
  try_run "smoke_ventas_ins.sh"
  try_run "smoke_pdf.sh"
} > "$OUT_DIR/12_smokes.txt" 2>&1 || true

# =========================
# 13) Generar HANDOVER.md
# =========================
log "Generando HANDOVER.md"
HANDOVER="$OUT_DIR/HANDOVER.md"

# Adjuntos de arquitectura
ARCH_FILES=()
[[ -f "$OUT_DIR/06_erd.png" ]] && ARCH_FILES+=("06_erd.png")
[[ -f "$OUT_DIR/06_erd.dot" ]] && ARCH_FILES+=("06_erd.dot")
[[ -f "$OUT_DIR/openapi.json" ]] && ARCH_FILES+=("openapi.json")

cat > "$HANDOVER" <<'MD'
# Handover Backend ISP – Diagnóstico y Artefactos

Este documento resume el estado actual del backend, los módulos implementados, el **esquema y estructura de BD**, los **endpoints** y **pendientes**. Se adjuntan artefactos (OpenAPI, ERD, dumps, muestras y logs) en el paquete generado por el script.

> **Ruta del paquete:** ver `*.tar.gz` generado junto a este directorio.

---

## 1) Cómo reproducir / entorno

- Docker compose orquesta: **api**, **db (Postgres)**, **minio**.
- Variables importantes:
  - `API_BASE_RAW` (default `http://localhost:3000`)
  - `API_BASE_V1` (default `http://localhost:3000/v1`)
  - `API_KEY` (x-api-key si corresponde)
  - `MINIO_EXTERNAL_URL` / `MINIO_PUBLIC_BASE` para firmas públicas
- Health:
  - `${API_BASE_RAW}/health`
  - `${API_BASE_V1}/health`

---

## 2) Módulos y flujos principales

- **Ventas**: crear → subir evidencias → pagar → genera INS + PDFs (recibo/contrato).
- **Agenda/Órdenes**: INS y cierre idempotente con descuento de stock (líneas).
- **Inventario**: kardex, ajustes, traslados, stock técnico con consistencia.
- **Técnico**: identidad del técnico y stock por técnico.
- **MinIO/PDF**: evidencias y PDFs (URLs firmadas).

---

## 3) Esquema de base de datos y tablas

Revisa:
- `05_db_catalog.txt` (catálogo general, tamaños, índices, constraints)
- `06_schema_tables.txt` (detalle `\d+ tabla` por cada una)
- `db_schema.sql` (dump schema)
- `db_seed.sql` (materiales, técnicos, stock, ordenes si existen)
- `sample_*.txt` (muestras de datos por tabla)

> Se adjunta **ERD** en `06_erd.dot` y `06_erd.png` (si Graphviz estaba disponible).

---

## 4) OpenAPI / Endpoints

- Archivo `openapi.json` si el extractor pudo obtenerlo.
- Extractos en `08_api.txt`.

Endpoints clave (público observado):
- `POST /v1/ventas`, `POST /v1/ventas/:codigo/evidencias`, `POST /v1/ventas/:codigo/pagar`
- `GET /v1/inventario/kardex`
- `GET /v1/ordenes/:codigo` (si existe)
- `POST /v1/agenda/ordenes/:codigo/reagendar` (según configuración)

---

## 5) Smokes y pruebas

- Logs de smokes: `12_smokes.txt`
- Extractos de tests: `09_tests.txt`

---

## 6) Pendientes y plan de cierre

- Idempotencia en handlers de inventario usando `Idempotency-Key`
- Órdenes por tipo (MAN, COR, REC, BAJ, TRA, CMB, RCT) con:
  - GET detalle, POST evidencias, POST cerrar con payload por tipo
  - PDF de cierre con bloques condicionales + firma
- Jobs administrativos (COR, REC, BAJ) y transición de estados de usuario
- Almacén principal CRUD + catálogos (materiales y equipos)
- Equipos con serial (ONT/Repe) y endpoints de disponibilidad/validaciones
- Roles simples (ventas/técnico/admin)
- E2E por caso de negocio y smokes de jobs

---

## 7) Archivos incluidos

- `01_repo.txt`, `02_docker.txt`, `03_env.txt`
- `04_backend.txt`, `04b_openapi.txt`, `openapi.json` (si se logró)
- `05_db_catalog.txt`, `06_schema_tables.txt`, `06_erd.dot`/`06_erd.png`
- `07_db_dumps.txt`, `db_schema.sql`, `db_seed.sql`, `sample_*.txt`
- `08_api.txt`, `09_tests.txt`, `10_minio.txt`, `11_summary.txt`, `12_smokes.txt`

> **Descargas externas**: asegúrate de que `MINIO_EXTERNAL_URL` apunte al host accesible públicamente para que los PDF/firmas sean descargables fuera del servidor.

---

## 8) Contacto / Notas

- Revisar `02_docker.txt` para ver imagenes y compose efectivos.
- Si falta OpenAPI, arranca la API y prueba `${API_BASE_RAW}/docs-json`.

MD

# =========================
# 14) Paquete comprimido
# =========================
tar czf "${OUT_DIR}.tar.gz" "$OUT_DIR"

# Imprime adjuntos relevantes encontrados
if [[ ${#ARCH_FILES[@]} -gt 0 ]]; then
  echo "Adjuntos de arquitectura: ${ARCH_FILES[*]}" >> "$OUT_DIR/00_index.txt"
fi

echo "👉 Paquete listo: ${OUT_DIR}.tar.gz"
