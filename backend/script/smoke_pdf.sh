#!/usr/bin/env bash
set -euo pipefail
API_BASE="${API_BASE:-http://localhost:3000}"; KEY="${KEY:-superdev}"
V1="$API_BASE/v1"; hdr=(-H "x-api-key: $KEY" -H "content-type: application/json")
PROBE_KEY="_probe/$(date +%s)-health.txt"
PUBLIC_BASE="${PUBLIC_BASE:-http://127.0.0.1:9000/evidencias/}"

wait_api(){ local h1 h2; for i in $(seq 1 40); do
  h1=$(curl -s -o /dev/null -w '%{http_code}' "$API_BASE/health" || echo 000)
  h2=$(curl -s -o /dev/null -w '%{http_code}' "${hdr[@]}" "$V1/health" || echo 000)
  [[ "$h1" == 200 || "$h2" == 200 ]] && return; sleep 0.3
done; echo "❌ API no respondió"; exit 1; }

echo "=== 🧪 smoke_pdf ==="
wait_api
code=$(curl -sS -o /tmp/pdf_put.json -w '%{http_code}' "${hdr[@]}" \
  -d "{\"key\":\"${PROBE_KEY}\",\"size\":5}" "$V1/pdf/probe-put")
[[ "$code" == "200" ]] || { echo "❌ /pdf/probe-put HTTP $code"; exit 1; }
jq -e '.ok==true and (.key|length>0)' </tmp/pdf_put.json >/dev/null
curl -fsS "${hdr[@]}" "$V1/pdf/probe" | jq -e '.ok==true and (.key|length>0)' >/dev/null
pub="${PUBLIC_BASE%/}/${PROBE_KEY}"
http=$(curl -s -o /dev/null -w '%{http_code}' "$pub" || echo 000)
if [[ "$http" == "200" ]]; then echo "✅ descarga pública OK (200)"; else echo "⚠️ descarga pública $http (tolerado)"; fi
echo "✅ smoke_pdf OK"
