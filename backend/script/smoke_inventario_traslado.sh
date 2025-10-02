#!/usr/bin/env bash
set -euo pipefail
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5433}"
DB_USER="${DB_USER:-ispuser}"
DB_PASS="${DB_PASS:-isppass}"
DB_NAME="${DB_NAME:-ispdb}"

export PGPASSWORD="$DB_PASS"

# Variables
principal=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT id FROM almacenes WHERE tipo='principal' LIMIT 1;")
tecnico6=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT id FROM almacenes WHERE tipo='tecnico' AND tecnico_id=6 LIMIT 1;")

echo "➡️ Traslado PRINCIPAL -> TÉCNICO 6"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT fn_mov_traslado('${principal}'::uuid, '${tecnico6}'::uuid, 3, 1, 'smoke auto traslado');"

echo "⬅️ Devolución TÉCNICO 6 -> PRINCIPAL"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT fn_mov_traslado('${tecnico6}'::uuid, '${principal}'::uuid, 3, 1, 'smoke auto devolución');"

echo "📦 Stock final del material 3"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT almacen_id, cantidad FROM stock_almacen WHERE material_id=3 ORDER BY cantidad DESC;"

echo "📑 Últimos movimientos (kárdex)"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT id, tipo, nota, cantidad FROM v_kardex ORDER BY fecha DESC, id DESC LIMIT 5;"
