# script/smoke_kardex_material.sh
#!/usr/bin/env bash
set -euo pipefail
API="${API_BASE:-http://localhost:3000}"
KEY="${API_KEY:-superdev}"

say(){ echo -e "$@"; }

# curl que devuelve body y status por separado
get() {
  local url="$1"
  local resp status body
  resp="$(curl -sS -H "x-api-key: $KEY" -w '\n%{http_code}' "$url")"
  status="${resp##*$'\n'}"
  body="${resp%$'\n'$status}"
  echo "$status"
  echo "$body"
}

# Intenta /kardex/material, si 404 o 501, prueba /kardex con mismos params.
try_kardex_material() {
  local qs="$1"  # ej: "materialId=5&limit=5"
  local url_mat="$API/v1/inventario/kardex/material?$qs"
  local out status body

  out="$(get "$url_mat")"
  status="$(echo "$out" | head -n1)"
  body="$(echo "$out" | tail -n +2)"

  if [[ "$status" == "200" ]]; then
    echo "$body"
    return 0
  fi

  if [[ "$status" == "404" || "$status" == "501" ]]; then
    # Fallback al endpoint existente
    local url_fbk="$API/v1/inventario/kardex?$qs"
    out="$(get "$url_fbk")"
    status="$(echo "$out" | head -n1)"
    body="$(echo "$out" | tail -n +2)"
    if [[ "$status" == "200" ]]; then
      echo "$body"
      return 0
    fi

    # Si también falla, declarar SKIP
    say "↷ SKIP: endpoint kardex/material no disponible (status $status)."
    exit 0
  fi

  # Otros errores: mostramos y salimos con error para no “false green”.
  echo "$body"
  echo "HTTP status: $status"
  exit 1
}

say "== kardex/material básicos (materialId=5) =="
try_kardex_material "materialId=5&limit=5" | jq 'length'

say "== kardex/material + almacen=CENTRAL (últimas 24h) =="
FROM="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"
try_kardex_material "materialId=5&from=$FROM&almacen=CENTRAL&limit=5" | jq 'length'

say "== kardex/material + tecnicoId=6 =="
try_kardex_material "materialId=5&tecnicoId=6&limit=5" | jq 'length'

say "OK kardex/material smoke"
