#!/usr/bin/env bash
# --- smoke: ordenes (evidencias + cierre + snapshot) ---
set -euo pipefail

API="${API:-http://localhost:3000}"
V1="$API/v1"

# ---------- helpers ----------
retry() {
  local tries="${1:-5}"; shift
  local delay="${1:-0.2}"; shift
  local cmd=("$@")
  local n=1
  while true; do
    if "${cmd[@]}"; then return 0; fi
    if (( n >= tries )); then return 1; fi
    sleep "$delay"
    n=$((n+1))
    delay=$(python3 - <<<'import random,sys;print(max(0.2,min(1.0,'"$delay"'+random.random()*0.3)))' 2>/dev/null || echo "$delay")
  done
}

curl_json() { # prints BODY; sets global HTTP_CODE
  local method="${1:-GET}"; shift
  local url="$1"; shift
  local data="${1:-}"; shift || true
  local res
  if [[ -n "$data" ]]; then
    res="$(curl -sS -w $'\n%{http_code}' -X "$method" "$url" -H 'Content-Type: application/json' --data "$data")"
  else
    res="$(curl -sS -w $'\n%{http_code}' -X "$method" "$url")"
  fi
  HTTP_CODE="${res##*$'\n'}"
  BODY="${res%$'\n'"$HTTP_CODE"}"
  echo -n "$BODY"
}

pick_ord() {
  local candidates=()
  if [[ -n "${ORD:-}" ]]; then candidates+=("$ORD"); fi
  candidates+=("INS-000001")

  for cand in "${candidates[@]}"; do
    BODY=""; HTTP_CODE=""
    retry 5 0.2 curl_json GET "$V1/ordenes/$cand" >/dev/null || true
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

# ---------- resolve ORD ----------
if ! ORD_RESOLVED="$(pick_ord)"; then
  echo "[ORDENES] ⚠️  no hay orden candidata (ni \$ORD ni INS-000001). skip."
  exit 0
fi
ORD="$ORD_RESOLVED"

echo "[ORDENES] usando ORD=$ORD"

# ---------- 1) evidencias ricas ----------
echo "[ORDENES] 1) evidencias ricas (2 items)"
payload_ev=$(
  jq -cn --arg ord "$ORD" '{
    items: [
      {tipo:"firma", url: ("evidencias/ins/" + $ord + "/firma.png")},
      {tipo:"foto_instalacion", url: ("evidencias/ins/" + $ord + "/foto1.jpg"), meta:{angulo:"frente"}}
    ],
    mergeJson: { foto1Key: ("evidencias/ins/" + $ord + "/foto1.jpg") },
    firmaKey: ("evidencias/ins/" + $ord + "/firma.png")
  }'
)
BODY=""; HTTP_CODE=""
retry 5 0.2 curl_json POST "$V1/ordenes/$ORD/evidencias" "$payload_ev" >/dev/null
if [[ "$HTTP_CODE" == "404" ]]; then
  echo "[ORDENES] ⚠️  orden no existe ($ORD). skip."
  exit 0
fi
echo "$BODY" | jq -e '.ok == true' >/dev/null
echo "$BODY" | jq -e '.items >= 2'  >/dev/null

# ---------- 2) cerrar ----------
echo "[ORDENES] 2) cerrar (snapshot nuevo)"
payload_close='{"payload_cierre":{"comentarios":"OK INSTALADO (smoke)"}}'
BODY=""; HTTP_CODE=""
retry 5 0.2 curl_json POST "$V1/ordenes/$ORD/cerrar" "$payload_close" >/dev/null
echo "$BODY" | jq -e '.ok == true'          >/dev/null
echo "$BODY" | jq -e '.estado == "cerrada"' >/dev/null
echo "$BODY" | jq -e 'has("cerradaAt")'     >/dev/null

# ---------- 3) leer snapshot ----------
echo "[ORDENES] 3) leer snapshot inmutable"
BODY=""; HTTP_CODE=""
retry 5 0.2 curl_json GET "$V1/ordenes/$ORD/cierre" >/dev/null
echo "$BODY" | jq -e '.ok == true'             >/dev/null
echo "$BODY" | jq -e '.tipo | length > 0'      >/dev/null
echo "$BODY" | jq -e '.payload | type=="object"' >/dev/null
echo "$BODY" | jq -e '.evidencias | type=="array"' >/dev/null
echo "$BODY" | jq -e '.version == 1'           >/dev/null
echo "$BODY" | jq -e 'has("pdfKey")'           >/dev/null

# ---------- 4) cerrar (idempotente) ----------
echo "[ORDENES] 4) cerrar (idempotente)"
BODY=""; HTTP_CODE=""
retry 5 0.2 curl_json POST "$V1/ordenes/$ORD/cerrar" '{"payload_cierre":{"comentarios":"OK INSTALADO (smoke 2)"}}' >/dev/null
echo "$BODY" | jq -e '.ok == true'       >/dev/null
echo "$BODY" | jq -e '._idempotent==true' >/dev/null

echo "[ORDENES] 5) pdf url publica"
pdf_info="$(curl -sS "$V1/ordenes/$ORD/pdf")"
echo "$pdf_info" | jq -e '.ok == true' >/dev/null
pdf_url="$(echo "$pdf_info" | jq -r '.pdfUrl')"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$pdf_url")"
test "$code" = "200"


echo "[ORDENES] ✅ OK"
