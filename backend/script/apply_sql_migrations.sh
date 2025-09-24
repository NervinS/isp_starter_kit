#!/usr/bin/env bash
set -euo pipefail

DB_USER="${POSTGRES_USER:-ispuser}"
DB_NAME="${POSTGRES_DB:-ispdb}"

# Ubicación del repo/backend (este script vive en backend/script/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Buscar archivos .sql en backend/sql (y también por compatibilidad en ../sql)
SQL_DIRS=("$BACKEND_DIR/sql" "$BACKEND_DIR/../sql")

SQL_FILES=()
for d in "${SQL_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    while IFS= read -r -d '' f; do SQL_FILES+=("$f"); done < <(find "$d" -maxdepth 1 -type f -name '*.sql' -print0)
  fi
done

# Orden alfabético
IFS=$'\n' SQL_FILES=($(sort <<<"${SQL_FILES[*]}")); unset IFS

if (( ${#SQL_FILES[@]} == 0 )); then
  echo "No hay archivos SQL para aplicar en: ${SQL_DIRS[*]}"
  exit 0
fi

for f in "${SQL_FILES[@]}"; do
  echo ">> aplicando: $f"
  # Enviar el contenido del archivo del host por STDIN al psql dentro del contenedor
  docker compose exec -T db sh -lc "psql -v ON_ERROR_STOP=1 -U '$DB_USER' -d '$DB_NAME'" < "$f"
done

echo "✓ Migraciones SQL aplicadas."
