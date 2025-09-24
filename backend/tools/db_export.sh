#!/usr/bin/env bash
set -euo pipefail

DB_SVC="db"   # nombre del servicio en docker compose
OUT="/tmp/db_export_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

echo "==> Dump de esquema (DDL)"
docker compose exec -T "$DB_SVC" sh -lc '
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -s
' > "$OUT/schema.sql"

echo "==> Seeds (datos mínimos útiles)"
# Catálogos y tablas operativas (ajusta si quieres más/menos)
TABLES=(
  catalogos
  catalogo_items
  materiales
  planes
  municipios
  sectores
  vias
  config_cargos
  tecnicos
  usuarios
  ventas
  ordenes
  orden_materiales
  evidencias
  inv_tecnico
  app_users
  smartolt_logs
  orden_cierres_idem
)
for t in "${TABLES[@]}"; do
  echo "-- $t" >> "$OUT/seeds.sql"
  docker compose exec -T "$DB_SVC" sh -lc "
    psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -c \"
    COPY (SELECT * FROM $t) TO STDOUT WITH CSV HEADER;
    \"
  " > "$OUT/${t}.csv" || true
done

# Script de carga de seeds desde CSVs (para entornos nuevos)
cat > "$OUT/restore_from_csv.sql" <<'SQL'
\set ON_ERROR_STOP on
-- Ajustar orden por FKs si hace falta
\copy catalogos          FROM 'catalogos.csv'          CSV HEADER
\copy catalogo_items     FROM 'catalogo_items.csv'     CSV HEADER
\copy materiales         FROM 'materiales.csv'         CSV HEADER
\copy planes             FROM 'planes.csv'             CSV HEADER
\copy municipios         FROM 'municipios.csv'         CSV HEADER
\copy sectores           FROM 'sectores.csv'           CSV HEADER
\copy vias               FROM 'vias.csv'               CSV HEADER
\copy config_cargos      FROM 'config_cargos.csv'      CSV HEADER
\copy tecnicos           FROM 'tecnicos.csv'           CSV HEADER
\copy usuarios           FROM 'usuarios.csv'           CSV HEADER
\copy ventas             FROM 'ventas.csv'             CSV HEADER
\copy ordenes            FROM 'ordenes.csv'            CSV HEADER
\copy orden_materiales   FROM 'orden_materiales.csv'   CSV HEADER
\copy evidencias         FROM 'evidencias.csv'         CSV HEADER
\copy inv_tecnico        FROM 'inv_tecnico.csv'        CSV HEADER
\copy app_users          FROM 'app_users.csv'          CSV HEADER
\copy smartolt_logs      FROM 'smartolt_logs.csv'      CSV HEADER
\copy orden_cierres_idem FROM 'orden_cierres_idem.csv' CSV HEADER
SQL

echo "==> Empaquetar export"
TARBALL="/tmp/db_export_bundle.tar.gz"
tar -C "$OUT" -czf "$TARBALL" .
echo "OK -> $TARBALL"
