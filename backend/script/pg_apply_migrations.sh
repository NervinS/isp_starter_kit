#!/usr/bin/env bash
set -euo pipefail

DB=${DB:-ispdb}
USER=${USER:-ispuser}

echo "==> Aplicando migraciones sql/*.sql al esquema ${DB} ..."
for f in $(ls -1 sql/*.sql 2>/dev/null | sort); do
  echo "---- $f"
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U "${USER}" -d "${DB}" -f "/app/$f" 2>&1 || {
    echo "ERROR aplicando $f"; exit 1;
  }
done
echo "==> OK migraciones."
