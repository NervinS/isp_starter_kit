#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
echo "== materiales/disponibles (CENTRAL) =="
curl -sL "$API/v1/materiales/disponibles?almacen=CENTRAL" | jq '.items[0]'
