#!/usr/bin/env bash
# smoke_ventas_ins.sh — Smoke de ventas → INS (creación, pago idempotente, asegurar, reagenda)
set -euo pipefail

API=${API:-http://localhost:3000}
JQ=${JQ:-jq}

hr() { printf "\n%s\n" "────────────────────────────────────────────────────────────────"; }
section() { hr; echo "👉 $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "Falta comando: $1"; exit 1; }; }
need curl
need "$JQ"

trap 'echo "❌ Falla en línea $LINENO"; exit 1' ERR

# Fecha para reagenda (YYYY-MM-DD). Por defecto: mañana UTC
AGENDA_D=${AGENDA_D:-$(date -u -d "+1 day" +"%Y-%m-%d" 2>/dev/null || date -u -v+1d +"%Y-%m-%d")}
TURN0=${TURN0:-am}

# Datos de venta (obligatorios en el API)
CLI_NOMBRE=${CLI_NOMBRE:-Ana}
CLI_APE=${CLI_APE:-Pérez}
DOC=${DOC:-CC123}
PLAN=${PLAN:-"FTTH 100M"}
MENSUAL=${MENSUAL:-"30"}
TOTAL=${TOTAL:-"30.00"}

# ────────────────────────────────────────────────────────────────
section "Healthcheck"
curl -sS -i "$API/health" | sed -n '1,20p'

# ────────────────────────────────────────────────────────────────
section "Crear venta (POST /v1/ventas)"
CREATE_BODY=$(cat <<JSON
{
  "cliente_nombre": "$CLI_NOMBRE",
  "cliente_apellido": "$CLI_APE",
  "documento": "$DOC",
  "plan": "$PLAN",
  "mensual_total": "$MENSUAL",
  "total": "$TOTAL"
}
JSON
)
RESP=$(curl -sS -i -X POST "$API/v1/ventas" \
  -H 'Content-Type: application/json' -d "$CREATE_BODY")
echo "$RESP" | sed -n '1,40p'
VENTA_COD=$(echo "$RESP" | sed '1,/^\r$/d' | $JQ -r '.codigo // empty')
if [[ -z "${VENTA_COD:-}" || "$VENTA_COD" == "null" ]]; then
  echo "❌ No se pudo crear la venta. Revisa el error arriba."
  exit 1
fi
echo "Venta: $VENTA_COD"

# ────────────────────────────────────────────────────────────────
section "Cargar evidencias (POST /v1/ventas/$VENTA_COD/evidencias)"
EV_BODY='{"cedula_img_key":"evidencias/ventas/CC123/cedula.png","recibo_img_key":"evidencias/ventas/CC123/recibo.png","firma_img_key":"evidencias/ventas/CC123/firma.png"}'
curl -sS -i -X POST "$API/v1/ventas/$VENTA_COD/evidencias" \
  -H 'Content-Type: application/json' -d "$EV_BODY" | sed -n '1,40p'

# ────────────────────────────────────────────────────────────────
section "Pagar venta (POST /v1/ventas/$VENTA_COD/pagar) con Idempotency-Key"
IDEMP="smoke-$(date +%s%N)"
RESP=$(curl -sS -i -X POST "$API/v1/ventas/$VENTA_COD/pagar" \
  -H "Idempotency-Key: $IDEMP" \
  -H 'Content-Type: application/json' -d '{}' )
echo "$RESP" | sed -n '1,60p'

# Mostrar estado post-pago
section "Estado post-pago (GET /v1/ventas/$VENTA_COD)"
curl -sS "$API/v1/ventas/$VENTA_COD" | $JQ .

# ────────────────────────────────────────────────────────────────
section "Asegurar INS 1a vez (POST /v1/ventas/$VENTA_COD/asegurar-ins)"
RESP=$(curl -sS -i -X POST "$API/v1/ventas/$VENTA_COD/asegurar-ins")
echo "$RESP" | sed -n '1,60p'
INS1=$(echo "$RESP" | sed '1,/^\r$/d' | $JQ -r '.codigo // .orden.codigo // empty')
if [[ -z "${INS1:-}" || "$INS1" == "null" ]]; then
  echo "❌ No se obtuvo código de INS."
  exit 1
fi
echo "INS: $INS1"

section "Asegurar INS 2a vez (idempotencia)"
RESP2=$(curl -sS -i -X POST "$API/v1/ventas/$VENTA_COD/asegurar-ins")
echo "$RESP2" | sed -n '1,60p'
INS2=$(echo "$RESP2" | sed '1,/^\r$/d' | $JQ -r '.codigo // .orden.codigo // empty')
if [[ "$INS1" == "$INS2" ]]; then
  echo "✅ OK idempotencia: $INS1"
else
  echo "❌ Idempotencia falló: $INS1 vs $INS2"
  exit 1
fi

# ────────────────────────────────────────────────────────────────
section "Consultar motivos de reagenda (GET /v1/catalogos/motivos-reagenda)"
RESP=$(curl -sS -i "$API/v1/catalogos/motivos-reagenda")
echo "$RESP" | sed -n '1,20p'
MOTIVO_ID=$(echo "$RESP" | sed '1,/^\r$/d' | $JQ -r 'if type=="array" and length>0 then .[0].id else empty end' || true)
if [[ -n "${MOTIVO_ID:-}" ]]; then
  echo "Motivo elegido: $MOTIVO_ID"
else
  echo "No hay motivos, continuaré sin motivoId (null)."
  MOTIVO_ID=null
fi

try_reagendar() {
  local payload="$1" label="$2"
  section "Re-agendar: $label → $AGENDA_D"
  echo "$payload" | $JQ .
  RESP=$(curl -sS -i -X POST "$API/v1/agenda/ordenes/$INS1/reagendar" \
    -H 'Content-Type: application/json' -d "$payload" || true)
  echo "$RESP" | sed -n '1,200p'
  local BODY; BODY=$(echo "$RESP" | sed '1,/^\r$/d')
  local WHEN; WHEN=$(echo "$BODY" | $JQ -r '.agendadoPara? // .fecha? // .orden?.agendadoPara? // empty' 2>/dev/null || true)
  local TURNO; TURNO=$(echo "$BODY" | $JQ -r '.turno? // .orden?.turno? // empty' 2>/dev/null || true)
  if [[ -n "$WHEN" && "$WHEN" != "null" ]]; then
    echo "✅ Reagenda OK → $WHEN${TURNO:+ (turno: $TURNO)}"
    return 0
  fi
  return 1
}

MID=$([ -n "${MOTIVO_ID:-}" ] && echo "$MOTIVO_ID" || echo null)

PAYLOAD1=$(cat <<JSON
{"fecha":"$AGENDA_D","turno":"$TURN0","motivoId":$MID}
JSON
)
PAYLOAD2=$(cat <<JSON
{"fecha":"$AGENDA_D","turno":"$TURN0","motivo_reagenda_id":$MID}
JSON
)
PAYLOAD3=$(cat <<JSON
{"fecha":"$AGENDA_D","turno":"$TURN0","motivoReagendaId":$MID}
JSON
)

if ! try_reagendar "$PAYLOAD1" "motivoId"; then
  if ! try_reagendar "$PAYLOAD2" "motivo_reagenda_id"; then
    if ! try_reagendar "$PAYLOAD3" "motivoReagendaId"; then
      echo "❌ No se pudo reagendar. Revisa el JSON de error arriba."
      exit 1
    fi
  fi
fi

# ────────────────────────────────────────────────────────────────
section "Detalle final de la INS (GET /v1/ordenes/$INS1) — validar agendadoPara"
DETAIL=$(curl -sS "$API/v1/ordenes/$INS1")
echo "$DETAIL" | $JQ .
AGP=$(echo "$DETAIL" | $JQ -r '.agendadoPara // .orden?.agendadoPara // empty')
if [[ -n "$AGP" && "$AGP" != "null" ]]; then
  echo "✅ La INS quedó agendada en: $AGP"
else
  echo "❌ La INS no quedó agendada (agendadoPara vacío)"
  exit 1
fi

hr
echo "🎉 Smoke completado: Venta $VENTA_COD → INS $INS1 (agendada)."
