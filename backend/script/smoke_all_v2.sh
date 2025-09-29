#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== 🧪 Runner E2E (v2) ==="
cd "$(dirname "$0")" && echo "📁 CWD: $PWD"

# Asegura permisos de ejecución para todos los smokes usados
chmod +x \
  smoke_inventory.sh \
  smoke_inventario_v2.sh \
  smoke_ordenes_v2.sh \
  smoke_agenda_v2.sh \
  smoke_tecnicos_cerrar_v2.sh

# Sube contenedores base
docker compose up -d db api minio >/dev/null

# Token por defecto (autenticación)
: "${TOKEN:=devtoken}"
export TOKEN

# Espera breve a que la API esté arriba (mejor UX en CI)
for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:3000/v1/health" >/dev/null; then break; fi
  sleep 1
done

# Orden sugerido:
# 1) smoke_inventory.sh (clásico)
# 2) smoke_inventario_v2.sh (verboso/kardex)
# 3) smoke_ordenes_v2.sh
# 4) smoke_agenda_v2.sh
# 5) smoke_tecnicos_cerrar_v2.sh
./smoke_inventory.sh
./smoke_inventario_v2.sh
./smoke_ordenes_v2.sh
./smoke_agenda_v2.sh
./smoke_tecnicos_cerrar_v2.sh

echo "✅ TODO OK"
