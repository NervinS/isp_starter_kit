#!/usr/bin/env bash
set -euo pipefail
docker compose exec -T db \
  psql -U ispuser -d ispdb -v ON_ERROR_STOP=1 \
  -f /app/script/sql/db_consistency_check.sql
