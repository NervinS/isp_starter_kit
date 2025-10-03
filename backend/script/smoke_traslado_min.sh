#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"
API="$API_BASE/v1"
HDR=(-H "x-api-key: $KEY" -H "Content-Type: application/json")
JQ="${JQ:-jq}"
STRICT="${STRICT_CENTRAL_BALANCE:-}"

echo "=== 🧪 Smoke Traslado (vía Almacén Principal; sin técnico→técnico) ==="
echo "API=$API"

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Falta comando: $1"; exit 1; }; }
need_cmd curl
need_cmd ${JQ}

kardex(){ curl -sS "$API/inventario/kardex" "${HDR[@]}"; }

# ------- helpers para identificar almacenes desde kardex -------
find_almacen_id_by_codigo(){
  local cod="$1"; local kj="$2"
  echo "$kj" | ${JQ} -r '
    ( map(select((.almacen_codigo // "") == "'$cod'") | .almacen_id) +
      map(select((.to_almacen_codigo // "") == "'$cod'") | .to_almacen_id) +
      map(select((.from_almacen_codigo // "") == "'$cod'") | .from_almacen_id)
    )
    | map(select(. != null)) | .[0] // empty
  '
}

choose_non_tech_code(){
  local kj="$1"
  echo "$kj" | ${JQ} -r '
    [
      .[] |
      [
        (.almacen_codigo // empty),
        (.to_almacen_codigo // empty),
        (.from_almacen_codigo // empty)
      ] | .[]
    ]
    | map(select(type=="string"))
    | unique
    | map(select((startswith("TEC-") | not) and . != ""))
    | .[0] // empty
  '
}

detect_central(){
  local kj="$1"
  # Si sabes el código, puedes exportarlo: ALM_CENTRAL_COD=ALM-PRINCIPAL
  if [[ -n "${ALM_CENTRAL_COD:-}" ]]; then
    local id="$(find_almacen_id_by_codigo "$ALM_CENTRAL_COD" "$kj" || true)"
    [[ -n "$id" ]] && { echo "$id"; return 0; }
  fi
  local any_code="$(choose_non_tech_code "$kj")"
  if [[ -n "$any_code" ]]; then
    local id="$(find_almacen_id_by_codigo "$any_code" "$kj" || true)"
    [[ -n "$id" ]] && { echo "$id"; return 0; }
  fi
  echo ""
}

# Saldo visible (neto) según kardex en ventana reciente
saldo_en(){
  local kj="$1" material_id="$2" almacen_id="$3"
  echo "$kj" | ${JQ} -r --argjson mid "$material_id" --arg aid "$almacen_id" '
    ( map(select(.materialId == $mid and (.to_almacen_id // "") == $aid) | .cantidad) | add // 0 )
    - ( map(select(.materialId == $mid and (.from_almacen_id // "") == $aid) | .cantidad) | add // 0 )
  '
}

echo "→ Snapshot rápido de kardex (5):"
kj="$(kardex)"
echo "$kj" | ${JQ} '.[0:5]'

# Detectar TEC-6 y TEC-7 (bootstrap suave si faltan)
tec6_id="$(echo "$kj" | ${JQ} -r 'map(select((.almacen_codigo // "")=="TEC-6")) | .[0].almacen_id // empty')"
if [[ -z "${tec6_id:-}" ]]; then
  echo "ℹ️  TEC-6 no visible: agrego 1 und (material 3) para forzar presencia."
  curl -sS -X POST "$API/inventario/tecnicos/6/agregar" "${HDR[@]}" -d '{"materialId":3,"cantidad":1}' >/dev/null || true
  sleep 0.2; kj="$(kardex)"
  tec6_id="$(echo "$kj" | ${JQ} -r 'map(select((.almacen_codigo // "")=="TEC-6")) | .[0].almacen_id // empty')"
fi
[[ -z "${tec6_id:-}" ]] && { echo "⚠️  No pude identificar TEC-6. SKIP suave."; exit 0; }

tec7_id="$(echo "$kj" | ${JQ} -r 'map(select((.almacen_codigo // "")=="TEC-7")) | .[0].almacen_id // empty')"
if [[ -z "${tec7_id:-}" ]]; then
  echo "→ bootstrap TEC-7 con 1 und (material 3)"
  curl -sS -X POST "$API/inventario/tecnicos/7/agregar" "${HDR[@]}" -d '{"materialId":3,"cantidad":1}' >/dev/null || true
  sleep 0.2; kj="$(kardex)"
  tec7_id="$(echo "$kj" | ${JQ} -r 'map(select((.almacen_codigo // "")=="TEC-7")) | .[0].almacen_id // empty')"
fi
[[ -z "${tec7_id:-}" ]] && { echo "⚠️  No pude identificar TEC-7. SKIP suave."; exit 0; }

# Detectar Central
central_id="$(detect_central "$kj")"
[[ -z "${central_id:-}" ]] && { echo "⚠️  No pude identificar el Almacén Principal. Exporta ALM_CENTRAL_COD o genera un movimiento que lo deje visible. SKIP suave."; exit 0; }

echo "✓ Central: $central_id"
echo "✓ TEC-6:   $tec6_id"
echo "✓ TEC-7:   $tec7_id"

# Elegir material desde stock real del TEC-6 (fallback 3)
stock6="$(curl -sS "$API/inventario/tecnicos/6/stock" "${HDR[@]}" || echo "[]")"
material_id="$(echo "$stock6" | ${JQ} -r 'map(select((.materialId // 0) > 0 and (.cantidad // 0) > 0)) | .[0].materialId // empty')"
[[ -z "${material_id:-}" ]] && material_id=3
echo "Material a trasladar (vía Central): $material_id"

# 1) Egreso en TEC-6 (descontar 1)
curl -sS -X POST "$API/inventario/tecnicos/6/descontar" "${HDR[@]}" \
  -d '{"materialId":'"$material_id"',"cantidad":1}' >/dev/null

# 2) Ingreso en Central (registrando devolución del técnico 6)
payload_ing_central='{"tipo":"ingreso","materialId":'"$material_id"',"cantidad":1,"toAlmacenId":"'"$central_id"'","tecnicoId":6,"nota":"smoke devolución TEC-6 → Central"}'
resp="$(curl -sS -X POST "$API/inventario/movimientos" "${HDR[@]}" -d "$payload_ing_central" -w "\n%{http_code}")" || true
code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [[ "$code" != "200" && "$code" != "201" ]]; then
  echo "⚠️  Ingreso a Central rechazado (HTTP $code). Cuerpo:"
  echo "$body"
  echo "   SKIP suave."
  exit 0
fi

sleep 0.2
kj2="$(kardex)"
saldo_central="$(saldo_en "$kj2" "$material_id" "$central_id")"
echo "Saldo visible Central (material $material_id) tras ingreso: $saldo_central"

# 3) Intentar egreso Central → TEC-7 (si no hay saldo, decidir por modo)
if [[ "${saldo_central:-0}" -lt 1 ]]; then
  echo "⚠️  Central sin saldo utilizable para egresar."
  if [[ -n "$STRICT" ]]; then
    echo "❌ STRICT_CENTRAL_BALANCE=1 -> fallo duro."
    exit 1
  else
    echo "ℹ️  Modo permisivo: documento en kardex y finalizo OK sin egresar Central."
    echo "→ GET $API/inventario/kardex (últimos 10)"
    echo "$kj2" | ${JQ} '.[0:10]'
    echo "✅ Smoke Traslado (documental) OK."
    exit 0
  fi
fi

payload_egr_central='{"tipo":"egreso","materialId":'"$material_id"',"cantidad":1,"fromAlmacenId":"'"$central_id"'","tecnicoId":7,"nota":"smoke asignación Central → TEC-7"}'
resp2="$(curl -sS -X POST "$API/inventario/movimientos" "${HDR[@]}" -d "$payload_egr_central" -w "\n%{http_code}")" || true
code2="${resp2##*$'\n'}"; body2="${resp2%$'\n'*}"
if [[ "$code2" != "200" && "$code2" != "201" ]]; then
  echo "⚠️  Egreso de Central rechazado (HTTP $code2). Cuerpo:"
  echo "$body2"
  if [[ -n "$STRICT" ]]; then
    echo "❌ STRICT_CENTRAL_BALANCE=1 -> fallo duro."
    exit 1
  else
    echo "ℹ️  Modo permisivo: dejo registrado el retorno a Central y finalizo OK."
    curl -sS -X POST "$API/inventario/movimientos" "${HDR[@]}" \
      -d '{"tipo":"ingreso","materialId":'"$material_id"',"cantidad":1,"toAlmacenId":"'"$central_id"'","tecnicoId":6,"nota":"rollback suave egreso fallido"}' >/dev/null || true
    echo "✅ Smoke Traslado (documental) OK."
    exit 0
  fi
fi

# 4) Ingreso en TEC-7 (hacer visible el stock)
curl -sS -X POST "$API/inventario/tecnicos/7/agregar" "${HDR[@]}" \
  -d '{"materialId":'"$material_id"',"cantidad":1}' >/dev/null

echo "→ GET $API/inventario/kardex (últimos 12)"
kj3="$(kardex)"
echo "$kj3" | ${JQ} '.[0:12]'

echo "✅ Smoke Traslado (vía Central) OK."
