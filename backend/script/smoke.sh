#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"

export API_BASE KEY

echo "=== 🧪 Smoke pack (básicos) ==="
echo "API_BASE=${API_BASE}  KEY=${KEY}"

# 1) Inventario mínimo (usa KEY internamente)
bash script/smoke_inventario_min.sh

# 2) Kardex mínimo
bash script/smoke_kardex_min.sh

# 3) Técnicos mínimo (arreglado 401)
bash script/smoke_tecnicos_min.sh

echo "✅ Todos los smokes OK"
