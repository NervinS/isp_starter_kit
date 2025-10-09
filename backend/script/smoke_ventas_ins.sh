#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://localhost:3000}"
V1="$API/v1"

banner() {
  echo
  echo "────────────────────────────────────────────────────────────────"
  echo "👉 $*"
}

uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen; else date +%s%N; fi
}

req() {
  # $1 = method, $2 = url, $3 = data-json (optional)
  local method="$1" url="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -i -H "Content-Type: application/json" -X "$method" "$url" -d "$data"
  else
    curl -sS -i -X "$method" "$url"
  fi
}

json() {
  # Extrae el body JSON de una respuesta con headers (-i)
  sed -n '/^\r\?$/,$p' | tail -n +2
}

must() {
  # Verifica que un campo exista y no sea null/"" en un JSON por stdin
  # uso: json | must '.foo'
  local jqexp="$1"
  local val
  val="$(jq -er "$jqexp")" || { echo "❌ Faltó campo requerido: $jqexp"; exit 1; }
  [ "$val" = "null" ] && { echo "❌ Campo nulo: $jqexp"; exit 1; }
  [ -z "$val" ] && { echo "❌ Campo vacío: $jqexp"; exit 1; }
  echo -n "$val"
}

echo
echo "=== 🧪 Smoke Ventas → Pago (idempotente) → Asegurar INS ===  API=$V1"

# 1) Health
banner "Healthcheck"
req GET "$API/health" | tee /dev/stderr | json | jq .

# 2) Crear venta (con payload completo para evitar 400)
banner "Crear venta (POST /v1/ventas)"
VENTA_PAYLOAD="$(jq -n --arg plan "FTTH 100M" --arg doc "CC$(shuf -i 100-999 -n 1)" '
  {
    cliente_nombre:"Ana",
    cliente_apellido:"Pérez",
    documento:$doc,
    plan:$plan,
    total:30.00
  }')"
CREA=$(req POST "$V1/ventas" "$VENTA_PAYLOAD" | tee /dev/stderr | json)
CODIGO=$(echo "$CREA" | must '.codigo')
echo "Venta: $CODIGO"

# 3) Evidencias
banner "Cargar evidencias (POST /v1/ventas/$CODIGO/evidencias)"
EVI_PAYLOAD='{
  "firma_key":"evidencias/ventas/CC123/firma.png",
  "cedula_key":"evidencias/ventas/CC123/cedula.png",
  "recibo_key":"evidencias/ventas/CC123/recibo.png"
}'
req POST "$V1/ventas/$CODIGO/evidencias" "$EVI_PAYLOAD" | tee /dev/stderr >/dev/null

# 4) Pagar con Idempotency-Key (dos veces, debe ser idempotente)
banner "Pagar venta (POST /v1/ventas/$CODIGO/pagar) con Idempotency-Key"
IDK="smoke-$(uuid)"
P1=$(curl -sS -H "Idempotency-Key: $IDK" -H "Content-Type: application/json" -X POST "$V1/ventas/$CODIGO/pagar" | tee /dev/stderr)
P2=$(curl -sS -H "Idempotency-Key: $IDK" -H "Content-Type: application/json" -X POST "$V1/ventas/$CODIGO/pagar" | tee /dev/stderr)

# 5) Estado post-pago
banner "Estado post-pago (GET /v1/ventas/$CODIGO)"
EST=$(req GET "$V1/ventas/$CODIGO" | json)
echo "$EST" | jq .
INS=$(echo "$EST" | jq -r '.orden.codigo // empty')
INS_ESTADO=$(echo "$EST" | jq -r '.orden.estado // empty')

# 6) Asegurar INS (idempotente)
banner "Asegurar INS 1a vez (POST /v1/ventas/$CODIGO/asegurar-ins)"
A1=$(req POST "$V1/ventas/$CODIGO/asegurar-ins" | json)
INS1=$(echo "$A1" | jq -r '.codigo // .orden.codigo // empty')
echo "INS: $INS1"

banner "Asegurar INS 2a vez (idempotencia)"
A2=$(req POST "$V1/ventas/$CODIGO/asegurar-ins" | json)
INS2=$(echo "$A2" | jq -r '.codigo // .orden.codigo // empty')
if [ -n "$INS1" ] && [ "$INS1" = "$INS2" ]; then
  echo "✅ OK idempotencia: $INS1"
else
  echo "❌ Idempotencia falló: $INS1 vs $INS2"; exit 1
fi

# 7) Si la INS quedó CERRADA, omitir reagenda prolijamente
if [ "${INS_ESTADO:-}" = "cerrada" ] || [ "$(echo "$A2" | jq -r '.estado // empty')" = "cerrada" ]; then
  banner "INS cerrada; reagenda no aplica"
  echo "ℹ️  La orden $INS1 está en estado=cerrada; se omite reagenda. ✅ OK"
  echo
  echo "🎉 Smoke ventas (cerrado sin reagenda): $CODIGO → $INS1 (estado=cerrada)"
  exit 0
fi

# 8) Si NO está cerrada, reagendar (verde cuando aplica)
banner "Consultar motivos de reagenda (GET /v1/catalogos/motivos-reagenda)"
MOT=$(req GET "$V1/catalogos/motivos-reagenda" | json)
echo "$MOT" | jq .
MOT_ID=$(echo "$MOT" | jq -r '.items[0].id // empty')
if [ -z "$MOT_ID" ] || [ "$MOT_ID" = "null" ]; then
  echo "No hay motivos, continuaré sin motivoId (null)."
  MOT_FIELD='"motivoId": null'
else
  MOT_FIELD='"motivoId": '"$MOT_ID"
  echo "Motivo elegido: $MOT_ID"
fi

DIA="$(date -u +%F)" # YYYY-MM-DD (hoy UTC)
banner "Re-agendar: motivoId → $DIA"
REAG_PAYLOAD="{\"fecha\":\"$DIA\",\"turno\":\"am\",$MOT_FIELD}"
echo "$REAG_PAYLOAD" | jq .
RAG=$(curl -sS -H "Content-Type: application/json" -X POST "$V1/agenda/ordenes/$INS1/reagendar" -d "$REAG_PAYLOAD" | tee /dev/stderr)

OK_AGENDA=$(echo "$RAG" | jq -r '.estado // empty')
if [ "$OK_AGENDA" = "agendada" ] || [ "$OK_AGENDA" = "reagendada" ] || [ -n "$(echo "$RAG" | jq -r '.agendadoPara // empty')" ]; then
  AGPARA="$(echo "$RAG" | jq -r '.agendadoPara // empty')"
  echo "✅ Reagenda OK → ${AGPARA:-$DIA} (turno: am)"
else
  echo "❌ No se pudo reagendar. Revisa el JSON de error arriba."
  exit 1
fi

# 9) Validación final
banner "Detalle final de la INS (GET /v1/ordenes/$INS1) — validar agendadoPara"
FIN=$(req GET "$V1/ordenes/$INS1" | json)
echo "$FIN" | jq .
AGP=$(echo "$FIN" | jq -r '.agendadoPara // empty')
if [ -n "$AGP" ]; then
  echo "✅ La INS quedó agendada en: $AGP"
fi

echo
echo "🎉 Smoke completado: Venta $CODIGO → INS $INS1 (estado=$(echo "$FIN" | jq -r '.estado'))."
