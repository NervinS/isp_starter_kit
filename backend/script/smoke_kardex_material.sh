# script/smoke_kardex_material.sh
#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"

say(){ echo -e "$@"; }
jq_len(){ jq 'length'; }

say "== kardex/material básicos (materialId=5) =="
curl -sL -H "x-api-key: $KEY" "$API/v1/inventario/kardex/material?materialId=5&limit=5" | tee /dev/stderr | jq_len

say "== kardex/material + almacen=CENTRAL (últimas 24h) =="
FROM="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"
curl -sL -H "x-api-key: $KEY" \
  "$API/v1/inventario/kardex/material?materialId=5&from=$FROM&almacen=CENTRAL&limit=5" \
  | tee /dev/stderr | jq_len

say "== kardex/material + tecnicoId=6 =="
curl -sL -H "x-api-key: $KEY" \
  "$API/v1/inventario/kardex/material?materialId=5&tecnicoId=6&limit=5" \
  | tee /dev/stderr | jq_len

say "OK kardex/material smoke"
