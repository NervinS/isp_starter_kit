#!/usr/bin/env sh
set -e

echo "Entrypoint: aplicando hotfix (si existe)…"
if [ -x /app/hotfix/patch-tecnicos.sh ]; then
  /app/hotfix/patch-tecnicos.sh || true
fi

echo "SMOKE_BYPASS_TECH_GUARD=${SMOKE_BYPASS_TECH_GUARD:-}"
exec node /app/dist/main.js
