#!/usr/bin/env bash
set -euo pipefail
API=${API:-http://localhost:3000/v1}

# Construir candidatos: primero una INS real, luego variables/semillas
candidates=()

real_ins="$(docker compose exec -T db psql -U ispuser -d ispdb -At -c \
"SELECT codigo FROM public.ordenes WHERE tipo='INS' ORDER BY created_at DESC LIMIT 1;")"
[[ -n "$real_ins" ]] && candidates+=("$real_ins")

[[ -n "${ORD:-}" ]] && candidates+=("$ORD")
candidates+=("INS-000001")  # último fallback

found=""
for c in "${candidates[@]}"; do
  status=$(curl -s -o /dev/null -w "%{http_code}" "$API/ordenes/$c")
  if [[ "$status" == "200" ]]; then
    found="$c"; break
  fi
done

if [[ -z "$found" ]]; then
  echo "[ORDENES] ⚠️  no hay orden candidata (ni \$ORD ni INS real). skip."
  exit 0
fi

echo "[ORDENES] usando $found"
# … resto del script …
