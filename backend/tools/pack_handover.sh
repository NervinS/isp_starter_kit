#!/usr/bin/env bash
set -euo pipefail

OUTDIR="/tmp/handover_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "==> 1) Árbol de directorios (sin node_modules/.next/.git)"
# Requiere util 'tree'; si no, usa 'find'
if command -v tree >/dev/null 2>&1; then
  tree -a -I 'node_modules|.next|.git|dist' > "$OUTDIR/PROJECT_TREE.txt" || true
else
  find . -maxdepth 6 -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.next/*' -not -path '*/dist/*' > "$OUTDIR/PROJECT_TREE.txt"
fi

echo "==> 2) package.json y lockfiles"
cp -f package.json "$OUTDIR/" 2>/dev/null || true
cp -f package-lock.json "$OUTDIR/" 2>/dev/null || true
cp -f pnpm-lock.yaml "$OUTDIR/" 2>/dev/null || true
cp -f yarn.lock "$OUTDIR/" 2>/dev/null || true

echo "==> 3) docker compose y .env (sanitizado)"
cp -f ../docker-compose.yml "$OUTDIR/" 2>/dev/null || true
# Sanitiza .env (si existe)
if [[ -f ../.env ]]; then
  sed -E 's/(PASSWORD|PASS|SECRET|KEY|TOKEN|ACCESS|CREDENTIALS)=.*/\1=REDACTED/gI' ../.env > "$OUTDIR/dotenv_sanitized.txt"
fi

echo "==> 4) Nest: rutas registradas (si hay Swagger en /api-json)"
# Esto asume backend expuesto en 3001
curl -s "http://localhost:3001/api-json" -o "$OUTDIR/openapi.json" || true
curl -s "http://localhost:3001/api" -o "$OUTDIR/swagger.html" || true

echo "==> 5) Vars de entorno efectivas (sanitizadas)"
env | sort | sed -E 's/(PASSWORD|PASS|SECRET|KEY|TOKEN|ACCESS|CREDENTIALS)=.*/\1=REDACTED/gI' > "$OUTDIR/env_runtime_sanitized.txt"

echo "==> 6) Versiones"
node -v > "$OUTDIR/VERSIONS.txt" 2>/dev/null || true
npm -v >> "$OUTDIR/VERSIONS.txt" 2>/dev/null || true
docker --version >> "$OUTDIR/VERSIONS.txt" 2>/dev/null || true
docker compose version >> "$OUTDIR/VERSIONS.txt" 2>/dev/null || true

echo "==> 7) README de handover"
cat > "$OUTDIR/README_HANDOVER.md" <<'MD'
# Handover ISP Starter Kit

## Qué incluye este paquete
- PROJECT_TREE.txt — Árbol del repo (sin node_modules/.next/dist/.git)
- package.json / lockfiles — Dependencias
- docker-compose.yml — Servicios
- dotenv_sanitized.txt — Variables de entorno sin secretos
- openapi.json / swagger.html — API (si estaba expuesto)
- env_runtime_sanitized.txt — Entorno efectivo sin secretos
- VERSIONS.txt — Versiones básicas

## Notas
- Ejecuta los scripts de `db_export` para obtener DDL y seeds de BD.
- Revisa `docs/` en el repo si existe para más diagramas/decisiones.
MD

echo "==> 8) Empaquetar"
TARBALL="/tmp/handover_bundle.tar.gz"
tar -C "$(dirname "$OUTDIR")" -czf "$TARBALL" "$(basename "$OUTDIR")"
echo "OK -> $TARBALL"
