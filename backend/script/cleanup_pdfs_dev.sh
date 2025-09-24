#!/usr/bin/env bash
set -euo pipefail
docker compose exec -T minio sh -lc '
  mc alias set local http://localhost:9000 minioadmin minioadmin >/dev/null 2>&1
  mc rm --recursive --force local/evidencias/ordenes || true
'
