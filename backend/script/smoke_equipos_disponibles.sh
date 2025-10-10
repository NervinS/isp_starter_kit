#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"
for t in ONU REPETIDOR ONT; do
  echo "== $t ==" >&2
  curl -s -H "x-api-key: $KEY" "$API/v1/equipos/disponibles?tipo=$t" | jq '.[0]'
done
