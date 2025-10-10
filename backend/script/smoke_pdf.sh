#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
V1="$API_BASE/v1"
hdr=(-H "x-api-key: $KEY" -H "content-type: application/json")

PROBE_KEY="_probe/$(date +%s)-health.txt"
PUBLIC_BASE="${PUBLIC_BASE:-http://127.0.0.1:9000/evidencias/}"

wait_api() {
  local h1 h2
  for i in $(seq 1 40); do
    h1=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/health" || echo 000)
    h2=$(curl -s -o /dev/null -w '%{http_code}' "${hdr[@]}" "$V1/health" || echo 000)
    [[ "$h1" == 200 || "$h2" == 200 ]] && return
    sleep 0.3
  done
  echo "❌ API no respondió"
  exit 1
}

echo "=== 🧪 smoke_pdf ==="
# Debug opcional
[[ "${PDF_DEBUG:-0}" == "1" ]] && set -x

wait_api

# 1) POST con querystring (backend actual). Si falla, fallback a POST con JSON (legacy).
code=$(curl -sS -o /tmp/pdf_put.json -w '%{http_code}' \
  "${hdr[@]}" -X POST \
  "$V1/pdf/probe-put?key=${PROBE_KEY}&size=5") || code=000

if [[ "${PDF_DEBUG:-0}" == "1" ]]; then
  echo "probe-put (QS POST) HTTP=$code"
  { echo "-- body --"; cat /tmp/pdf_put.json 2>/dev/null || true; echo; } || true
fi

if [[ "$code" != "200" ]]; then
  code=$(curl -sS -o /tmp/pdf_put.json -w '%{http_code}' \
    "${hdr[@]}" \
    -d "{\"key\":\"${PROBE_KEY}\",\"size\":5}" \
    "$V1/pdf/probe-put") || code=000
  if [[ "${PDF_DEBUG:-0}" == "1" ]]; then
    echo "probe-put (JSON POST) HTTP=$code"
    { echo "-- body --"; cat /tmp/pdf_put.json 2>/dev/null || true; echo; } || true
  fi
fi

[[ "$code" == "200" ]] || { echo "❌ /pdf/probe-put HTTP $code"; exit 1; }

# 2) Validación tolerante del body
[[ "${PDF_DEBUG:-0}" == "1" ]] && { echo "— /pdf/probe-put body (post) —"; cat /tmp/pdf_put.json; echo; }
jq -e 'type=="object"' </tmp/pdf_put.json >/dev/null
jq -e '( (has("key") and (.key|type=="string") and (.key|length>0))
      or (has("url") and (.url|type=="string") and (.url|length>0))
      or (has("ok") and .ok==true) )' </tmp/pdf_put.json >/dev/null

# 3) /pdf/probe debe responder ok y dar una key utilizable
curl -fsS "${hdr[@]}" "$V1/pdf/probe" | jq -e '.ok==true and (.key|length>0)' >/dev/null

# 4) Descarga pública (tolerada si no hay MinIO)
pub="${PUBLIC_BASE%/}/${PROBE_KEY}"
http=$(curl -s -o /dev/null -w '%{http_code}' "$pub" || echo 000)
if [[ "$http" == "200" ]]; then
  echo "✅ descarga pública OK (200)"
else
  echo "⚠️ descarga pública $http (tolerado)"
fi

echo "✅ smoke_pdf OK"
