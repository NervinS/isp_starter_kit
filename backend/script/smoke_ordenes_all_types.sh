#!/usr/bin/env bash
# script/smoke_ordenes_all_types.sh
set -euo pipefail

echo "=== 🧪 smoke_ordenes_all_types ==="
API="${API:-http://localhost:3000/v1}"

PSQL="docker compose exec -T db psql -U ispuser -d ispdb -At -X -q"
TYPES=(INS MAN COR REC BAJ TRA CMB RCT)

ok_cnt=0
sk_cnt=0
fail_cnt=0

for T in "${TYPES[@]}"; do
  CODE="$($PSQL -c "SELECT codigo FROM public.ordenes WHERE tipo='${T}' ORDER BY created_at DESC LIMIT 1;")" || true
  if [[ -z "${CODE// }" ]]; then
    echo "→ ${T}-???? :: SKIP (no hay órdenes de tipo ${T})"
    ((sk_cnt++)) || true
    continue
  fi

  echo "→ ${T} :: GET /ordenes/${CODE}"
  set +e
  resp="$(curl -sS -w '\n%{http_code}' "${API}/ordenes/${CODE}")"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "✗ curl error (exit=$rc)"
    ((fail_cnt++)) || true
    continue
  fi

  status="${resp##*$'\n'}"
  body="${resp%$'\n'$status}"

  if [[ "$status" != 2* ]]; then
    echo "$body"
    echo "✗ HTTP $status"
    ((fail_cnt++)) || true
  else
    echo "✓ ${T} OK"
    ((ok_cnt++)) || true
  fi
done

echo "-- resumen: ok=${ok_cnt} skip=${sk_cnt} fail=${fail_cnt}"
if [[ $fail_cnt -gt 0 ]]; then
  exit 22
fi
echo "✅ smoke_ordenes_all_types OK"
