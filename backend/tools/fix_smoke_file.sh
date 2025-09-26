#!/usr/bin/env bash
set -euo pipefail
FILE="${1:-smoke_tecnicos_cerrar_v2.sh}"
[[ -f "$FILE" ]] || { echo "No existe $FILE"; exit 1; }

# 1) Quitar líneas basura típicas que vi en tus logs
#    (si aparece más ruido, añade más -e '/regex/d')
sed -i -E \
  -e '/fiexit[[:space:]]*1/d' \
  -e '/------pty/d' \
  -e "/nicoId\\\\\":\\\\\"\\$TEC_ID\\\\\"\\}\"\\} >/d" \
  -e "/ada'\\);\\\" \\\\>/d" \
  "$FILE"

# 2) Normalizar retornos de carro (por si hubo CRLF o ^M)
sed -i 's/\r$//' "$FILE"

# 3) Reescribir limpia la función head_ok() completa (por si quedó truncada)
awk '
  BEGIN { in_head=0 }
  /head_ok\(\)\s*{/ { print "head_ok() {"; print "  local key=\"$1\""; print "  [[ -z \"${key:-}\" ]] && return 1"; print "  local url=\"${BASE%/}/${key#/}\""; print "  local code; code=\"$(curl -sS -o /dev/null -w '\''%{http_code}'\'' -I \"$url\" || true)\""; print "  [[ \"$code\" == \"200\" ]]"; in_head=1; next }
  in_head==1 {
    if ($0 ~ /^}/) { print "}"; in_head=0; next }
    else { next } # omitir el contenido viejo corrupto
  }
  { print $0 }
' "$FILE" > "${FILE}.fixed"

mv "${FILE}.fixed" "$FILE"
chmod +x "$FILE"
echo "Archivo saneado: $FILE"
