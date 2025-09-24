#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
OID="${STRESS_OID:-MAN-000001}"
TEC_CODE="${STRESS_TEC_CODE:-TEC-0001}"
MAT_CODE="${STRESS_MAT_CODE:-MAT-0001}"
PAR="${STRESS_PAR:-8}"

echo "[stress] API_BASE=$API_BASE  OID=$OID  TEC_CODE=$TEC_CODE  MAT_CODE=$MAT_CODE  PAR=$PAR"

# sanity
curl -fsS "$API_BASE/v1/health" >/dev/null && echo "[stress] health OK"

# por ahora stress simple: bombardear /health. (Mantiene contorno del proyecto)
URL="$API_BASE/v1/health"
echo "[stress] lanzando $PAR peticiones en paralelo a: $URL"
seq "$PAR" | xargs -I{} -P "$PAR" sh -c "curl -fsS '$URL' >/dev/null && printf . || printf x"
echo
echo "[stress] OK"
