#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== 🧪 Runner E2E (v2) ==="
cd "$(dirname "$0")" && echo "📁 CWD: $PWD"

chmod +x smoke_ordenes_v2.sh smoke_agenda_v2.sh smoke_tecnicos_cerrar_v2.sh

./smoke_ordenes_v2.sh
./smoke_agenda_v2.sh
./smoke_tecnicos_cerrar_v2.sh

echo "✅ TODO OK"
