#!/usr/bin/env bash
set -euo pipefail

PSQL='docker compose exec -T db psql -U ispuser -d ispdb -qAt -c'

fail=0

# 1) Índices clave (case-insensitive)
wanted_idxs=(
  idx_usuarios_estado
  idx_ca61f54e17be66859316ac5d87
  idx_aa8405c6457229608b11ba1460
  idx_11ee5476fd4f40aeac06660adf
  ux_orden_materiales_orden_mat
  ux_materiales_codigo
  idx_003ee7bf976605547308b3d58b
  idx_d69a8b13b58fcfa4a03dcc738b
  idx_2a6ea126337a50ff6015bfecc5
  idx_5d67cc2e38c80255e768c2b76a
)

for idx in "${wanted_idxs[@]}"; do
  present="$($PSQL "SELECT indexname FROM pg_indexes WHERE schemaname='public' AND lower(indexname)='${idx}'")" || true
  if [[ -z "$present" ]]; then
    echo "FALTA índice: $idx"; fail=1
  fi
done

# 2) FKs de inv_tecnico
fk_count="$($PSQL "SELECT count(*) FROM pg_constraint WHERE conrelid='public.inv_tecnico'::regclass AND contype='f'")"
[[ "$fk_count" = "2" ]] || { echo "FKs inv_tecnico esperadas=2, actual=$fk_count"; fail=1; }

# 3) Unicidad en municipios
uniq_count="$($PSQL "SELECT count(*) FROM pg_constraint WHERE conrelid='public.municipios'::regclass AND contype='u'")"
[[ "$uniq_count" = "2" ]] || { echo "Uniques municipios esperadas=2, actual=$uniq_count"; fail=1; }

# 4) Migraciones registradas
need=("InitSchema1758484018068" "InventarioHardening1720000000000" "InitSchema1758483929082")
for m in "${need[@]}"; do
  have="$($PSQL "SELECT 1 FROM public.typeorm_migrations WHERE name='${m}' LIMIT 1")" || true
  [[ "$have" = "1" ]] || { echo "FALTA migración en tabla typeorm_migrations: $m"; fail=1; }
done

if [[ "$fail" -ne 0 ]]; then
  echo "Smoke test: FALLÓ ❌"; exit 1
else
  echo "Smoke test: OK ✅"; exit 0
fi
