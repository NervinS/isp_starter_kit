#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://127.0.0.1:3000}"
echo "▶ Catalogos mini"
curl -sf "$API/v1/catalogos/motivos-reagenda" >/dev/null
curl -sf "$API/v1/catalogos/motivos_reagenda/items?soloActivos=true" >/dev/null
echo "✓ Catalogos mini OK"
