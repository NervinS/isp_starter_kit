#!/usr/bin/env bash
set -Eeuo pipefail
echo "=== 🚦 Smoke Órdenes ==="
cd "$(dirname "$0")/.." && echo "📁 CWD: $PWD"

API="http://127.0.0.1:3000/v1"
psqlq='docker compose -f docker-compose.yml exec -T db psql -qAtX -U ispuser -d ispdb -c'

# Levantar
docker compose -f docker-compose.yml up -d db api >/dev/null

# Espera robusta (hasta 60s) para que no "reset by peer" si la API reinicia
echo "⏳ API..."
for i in {1..60}; do
  if curl -fsS "$API/health" >/dev/null; then break; fi
  sleep 1
done
curl -fsS "$API/health" >/dev/null || { echo "❌ API no respondió /v1/health"; exit 1; }

USR_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;")"
[ -n "$USR_ID" ] || { echo "❌ sin usuarios"; exit 1; }

req(){ local m="$1" u="$2" d="${3-}" o
  if [[ -n "${d}" ]]; then o="$(curl -sS -X "$m" "$u" -H 'Content-Type: application/json' -d "$d")"
  else o="$(curl -sS -X "$m" "$u")"; fi
  if echo "$o" | jq -e '.statusCode? // empty' >/dev/null; then echo "$o" | jq .; exit 1; fi
  echo "$o"
}

echo -e "\n== CORTE =="
out="$(req POST "$API/ordenes" "{\"usuarioId\":\"$USR_ID\",\"tipo\":\"COR\"}")"
echo "$out" | jq .
cod="$(echo "$out" | jq -r '.orden.codigo // .orden[0].codigo')"
det="$(req GET "$API/ordenes/$cod")"
estado="$(echo "$det" | jq -r '.orden.estado')"
echo "estado=$estado"
[[ "$estado" == "cerrada" ]] || { echo "❌ COR no cerrada"; exit 1; }

echo -e "\n== MANTENIMIENTO (crear + cerrar) =="
out="$(req POST "$API/ordenes" "{\"usuarioId\":\"$USR_ID\",\"tipo\":\"MAN\"}")"
cod="$(echo "$out" | jq -r '.orden.codigo // .orden[0].codigo')"
echo "COD=$cod"

close="$(req POST "$API/ordenes/$cod/cerrar" '{
  "diagnostico":"Trabajo ok",
  "servicio":{"ponSn":"PON123","planMbps":200,"tv":false,"estandarWifi":"wifi6","roseta":true,"marquilla":"APTO-301"},
  "materiales":[{"materialCodigo":"DROP","cantidad":10},{"materialCodigo":"CONECT_FO","cantidad":2}],
  "evidencias":[{"tipo":"foto","url":"http://127.0.0.1:9000/evidencias/f1.jpg"},{"tipo":"firma","url":"http://127.0.0.1:9000/evidencias/sign.png"}]
}')"
echo "$close" | jq .
est="$(echo "$close" | jq -r '.orden.estado')"
echo "estado=$est"
[[ "$est" == "cerrada" ]] || { echo "❌ MAN no cerrada"; exit 1; }

echo -e "\n✅ Smoke Órdenes OK"
