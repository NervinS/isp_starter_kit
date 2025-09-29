#!/usr/bin/env bash
set -euo pipefail

OUT="diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

echo "== Versions ==" | tee "$OUT/00_versions.txt"
node -v        | tee -a "$OUT/00_versions.txt"
npm -v         | tee -a "$OUT/00_versions.txt"
psql --version | tee -a "$OUT/00_versions.txt"
docker --version | tee -a "$OUT/00_versions.txt"
git rev-parse --short HEAD | sed 's/^/git_commit: /' | tee -a "$OUT/00_versions.txt"

echo "== Containers ==" | tee "$OUT/01_containers.txt"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | tee -a "$OUT/01_containers.txt"

echo "== Env =="
( set -o posix ; set ) | grep -E '^(NODE_ENV|DATABASE_URL|DB_|MINIO_|S3_|NEST_|PORT)=' | sort > "$OUT/02_env_sanitized.txt" || true

echo "== API /health ==" | tee "$OUT/03_health.txt"
curl -sS http://127.0.0.1:3000/v1/health | tee -a "$OUT/03_health.txt" || true

echo "== DB snapshots ==" | tee "$OUT/10_db.txt"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' | tee -a "$OUT/10_db.txt"
-- Almacenes principal/técnico y técnico asociado
TABLE almacenes;
-- Stock del material 3 en ambos almacenes y espejo inv_tecnico
SELECT a.id AS almacen_id, a.tipo, a.tecnico_id,
       sa.material_id, sa.cantidad AS stock_almacen,
       it.cantidad AS inv_tecnico
FROM   almacenes a
LEFT JOIN stock_almacen sa
  ON sa.almacen_id=a.id AND sa.material_id=3
LEFT JOIN inv_tecnico it
  ON it.tecnico_id=a.tecnico_id AND it.material_id=3
WHERE a.tipo IN ('principal','tecnico')
ORDER BY a.tipo;

-- Desviaciones (vista usada por el smoke)
SELECT * FROM v_desviacion_inv_tecnico WHERE diff <> 0 ORDER BY tecnico_id, material_id;

-- Últimos kardex del material 3
SELECT * FROM v_kardex WHERE material_id=3 ORDER BY created_at DESC LIMIT 30;

-- Ordenes MAN de la corrida DUP y sus OM
SELECT o.codigo, o.estado, om.material_id, om.cantidad, om.descontado
FROM ordenes o
LEFT JOIN orden_materiales om ON om.orden_id=o.id
WHERE o.codigo LIKE 'MAN-%-DUP'
ORDER BY o.codigo, om.material_id;

-- Idempotencia (si existe esta tabla/columna en tu esquema)
SELECT * FROM idempotency_keys
WHERE key LIKE 'cerrar:%'
ORDER BY created_at DESC LIMIT 50;
SQL

echo "== Logs containers ==" | tee "$OUT/20_logs.txt"
docker logs isp-api --since=2h > "$OUT/20_api.log" 2>&1 || true
docker logs isp-db  --since=2h > "$OUT/20_db.log"  2>&1 || true
docker logs isp-minio --since=2h > "$OUT/20_minio.log" 2>&1 || true

tar -czf "${OUT}.tar.gz" "$OUT"
echo "📦 Generado: ${OUT}.tar.gz"
