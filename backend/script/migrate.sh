#!/usr/bin/env bash
# Ejecuta migraciones de TypeORM directamente desde TypeScript
# Uso: ./script/migrate.sh

set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 🧱 Running DB migrations (TS) =="
docker compose run --rm migrator
echo "== ✅ Migrations done =="
