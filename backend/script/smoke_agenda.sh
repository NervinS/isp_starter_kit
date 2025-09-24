#!/usr/bin/env bash
set -Eeuo pipefail

# 🔒 Fijamos compose y ruta absolutas: no depende del directorio desde el que lo ejecutes
ROOT="/home/yarumo/isp_starter_kit/backend"
COMPOSE="docker compose -f $ROOT/docker-compose.yml -p backend"
API="http://127.0.0.1:3000/v1"
psqlq="$COMPOSE exec -T db psql -qAtX -U ispuser -d ispdb -c"

echo "=== 🚦 Smoke Agenda (final) ==="
echo "📁 Using compose at: $ROOT/docker-compose.yml"

die(){ echo "❌ $*" >&2; exit 1; }
req(){ local m="$1" u="$2" d="${3-}" o
  if [[ -n "$d" ]]; then o="$(curl -sS -X "$m" "$u" -H 'Content-Type: application/json' -d "$d")"
  else o="$(curl -sS -X "$m" "$u")"; fi
  if echo "$o" | jq -e '.statusCode? // empty' >/dev/null; then echo "$o" | jq .; die "API error"; fi
  echo "$o"
}

# Sube servicios correctos de ESTE compose
$COMPOSE up -d db minio api >/dev/null

echo "⏳ Esperando API..."
for i in {1..60}; do curl -fsS "$API/health" >/dev/null && break || sleep 1; done || die "API no respondió a tiempo"

echo "== 0) Motivos =="
catm="$(req GET "$API/catalogos/motivos-reagenda")"
echo "$catm" | jq '{ok, count:(.items|length)}'
MOTIVO="$(echo "$catm" | jq -r '.items[]?.codigo' | (grep -x 'cliente-ausente' || head -n1))"
[[ -n "$MOTIVO" ]] || die "Catálogo vacío"
echo "🎯 motivo: $MOTIVO"

TECNICO_ID="$($psqlq "SELECT id FROM tecnicos LIMIT 1;")"
USUARIO_ID="$($psqlq "SELECT id FROM usuarios LIMIT 1;")"
[[ -n "$TECNICO_ID" && -n "$USUARIO_ID" ]] || die "Faltan técnico/usuario"

echo "== 1) Crear orden =="
OID="$($COMPOSE exec -T db sh -lc "psql -qAtX -U ispuser -d ispdb -c \"
INSERT INTO ordenes (id,codigo,estado,tecnico_id,tipo,subtotal,total,usuario_id)
VALUES (uuid_generate_v4(), DEFAULT, 'agendada', '${TECNICO_ID}', 'INS', 0, 0, '${USUARIO_ID}')
RETURNING id;\"")"
COD="$($psqlq "SELECT codigo FROM ordenes WHERE id='${OID}';")"
[[ -n "$COD" ]] || die "No se obtuvo código"
echo "🆕 orden: $COD"

TOM="$(date -u -d '+1 day' +%F 2>/dev/null || date -u -v+1d +%F)"
DAY2="$(date -u -d '+2 day' +%F 2>/dev/null || date -u -v+2d +%F)"

echo "== 2) ASIGNAR =="
req POST "$API/agenda/ordenes/${COD}/asignar" "{\"fecha\":\"$TOM\",\"turno\":\"am\",\"tecnicoId\":\"$TECNICO_ID\"}" | jq .

echo "== 3) REAGENDAR (con motivo) =="
req POST "$API/agenda/ordenes/${COD}/reagendar" "{\"fecha\":\"$DAY2\",\"turno\":\"pm\",\"motivo\":\"Cliente reprograma\",\"motivoCodigo\":\"$MOTIVO\"}" | jq .

echo "== 3b) DB post-reagendar =="
$psqlq "SELECT to_char(agendado_para,'YYYY-MM-DD'), turno, motivo_reagenda, motivo_reagenda_codigo FROM ordenes WHERE codigo='${COD}';" \
| awk -F'|' '{printf "agendado_para=%s | turno=%s | motivo_reagenda=%s | motivo_reagenda_codigo=%s\n",$1,$2,$3,$4}'

MT="$($psqlq "SELECT motivo_reagenda FROM ordenes WHERE codigo='${COD}';")"
MC="$($psqlq "SELECT motivo_reagenda_codigo FROM ordenes WHERE codigo='${COD}';")"
[[ "$MT" == "Cliente reprograma" && "$MC" == "$MOTIVO" ]] || die "Persistencia de motivo reagenda incorrecta"

echo "== 4) CANCELAR =="
req POST "$API/agenda/ordenes/${COD}/cancelar" | jq .

echo "== 5) ANULAR =="
req POST "$API/agenda/ordenes/${COD}/anular" "{\"motivo\":\"Cliente desistió\",\"motivoCodigo\":\"$MOTIVO\"}" | jq .

echo "✅ Smoke Agenda OK"
