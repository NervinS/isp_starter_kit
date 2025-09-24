# Guarda esto como diag.sh dentro de isp_starter_kit/backend y ejecútalo con:  bash diag.sh | tee diag.log
set -euo pipefail

section() { printf '\n\n===== %s =====\n' "$*" ; }

# 0) Contexto general
section "0) Contexto general"
echo "pwd=$(pwd)"
echo "date=$(date -Is)"
echo "whoami=$(whoami)"
echo "uname=$(uname -a || true)"

# 1) Docker / Compose / Imágenes
section "1) Docker / Compose"
docker --version || true
docker compose version || true
echo
echo "---- docker-compose.yml (si existe) ----"
[ -f docker-compose.yml ] && sed -n '1,200p' docker-compose.yml || echo "no docker-compose.yml"
echo
echo "---- docker compose config (normalizado) ----"
docker compose config || true

# 2) Estado de contenedores y logs breves
section "2) Estado de contenedores"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
echo
echo "---- Logs últimos 2 min (api/db/minio si existen) ----"
docker compose logs --since=2m db api minio 2>/dev/null || true

# 3) Puertos del host (5432/5433/3000) y procesos escuchando
section "3) Puertos del host (5432/5433/3000)"
( command -v ss >/dev/null && ss -lntp || netstat -lntp ) 2>/dev/null | egrep ':5432|:5433|:3000' || true

# 4) Variables importantes dentro del contenedor api (si corre)
section "4) Entorno dentro de api (si está levantado)"
if docker compose ps api --format '{{.State}}' 2>/dev/null | grep -q running; then
  docker compose exec -T api sh -lc 'node -v && npm -v && env | egrep "NODE_ENV|DATABASE_URL|MINIO|SMOKE" || true'
  docker compose exec -T api sh -lc 'ls -la /app && ls -la /app/dist || true'
else
  echo "api no está running"
fi

# 5) Versiones Node en host (por si compilas afuera)
section "5) Node/NPM en host"
( node -v && npm -v ) || echo "node/npm no instalados en host (ok si solo usas docker)"

# 6) Paquetes y scripts NPM
section "6) package.json & lock"
[ -f package.json ] && cat package.json || echo "no package.json"
[ -f package-lock.json ] && echo "(package-lock existe)" || echo "no package-lock.json"

# 7) TS config
section "7) tsconfig.json / tsconfig.build.json"
[ -f tsconfig.json ] && sed -n '1,200p' tsconfig.json || echo "no tsconfig.json"
[ -f tsconfig.build.json ] && sed -n '1,200p' tsconfig.build.json || echo "no tsconfig.build.json"

# 8) Archivos fuente vinculados a los errores de compilación
section "8) Archivos TS (errores reportados)"
for f in \
  src/modules/ordenes/ordenes.service.ts \
  src/modules/ordenes/entities/orden.entity.ts \
  src/modules/ordenes/entities/orden-material.entity.ts \
  src/modules/materiales/orden-material.entity.ts \
  src/modules/tecnicos/tecnicos.service.ts \
  src/modules/tecnicos/tecnicos.controller.ts \
  src/modules/tecnicos/tecnicos.module.ts \
  src/modules/tecnicos/dto/cerrar-orden.dto.ts
do
  if [ -f "$f" ]; then
    echo "--- $f ---"
    nl -ba "$f" | sed -n '1,220p'
  else
    echo "--- $f (NO ENCONTRADO) ---"
  fi
done

# 9) Grep por props conflictivas en src (camelCase / columnas snake_case)
section "9) Grep de props conflictivas en src/"
if [ -d src ]; then
  egrep -Rni --color=never "evidencias|firmaImgKey|snapshotTecnico|materiales\s*:" src || true
else
  echo "no existe src/"
fi

# 10) Dist ensamblado (para ver qué quedó compilado)
section "10) Grep en dist/ (si existe)"
if [ -d dist ]; then
  egrep -Rni --color=never "evidencias|firmaImgKey|snapshotTecnico" dist || true
  echo
  [ -f dist/modules/tecnicos/tecnicos.service.js ] && nl -ba dist/modules/tecnicos/tecnicos.service.js | sed -n '1,160p' || true
else
  echo "no existe dist/ (normal si el build falló)"
fi

# 11) Esquema de base de datos (solo lectura)
section "11) Esquema DB (si db está arriba)"
if docker compose ps db --format '{{.State}}' 2>/dev/null | grep -q running; then
  docker compose exec -T db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\d+ ordenes" || true'
  docker compose exec -T db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\d+ orden_materiales" || true'
  docker compose exec -T db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM ordenes ORDER BY creado_at DESC NULLS LAST LIMIT 3;" || true'
else
  echo "db no está running"
fi

# 12) Dockerfile actual
section "12) Dockerfile actual"
[ -f Dockerfile ] && sed -n '1,200p' Dockerfile || echo "no Dockerfile"

# 13) Ramas de Git y cambios locales (no altera nada)
section "13) Git status (si es repo git)"
if command -v git >/dev/null && [ -d .git ]; then
  git rev-parse --abbrev-ref HEAD || true
  git status --porcelain || true
  echo
  git log -1 --oneline || true
else
  echo "no es repo git (o sin git cli)"
fi

# 14) Salud de endpoints (si la API está arriba)
section "14) Salud de endpoints (curl)"
if docker compose ps api --format '{{.State}}' 2>/dev/null | grep -q running; then
  curl -sS http://localhost:3000/v1/health || true
  echo
  echo "(si hay token/guard, el health puede requerir headers, es solo ping)"
else
  echo "api no está running"
fi

section "FIN"

