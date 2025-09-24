#!/usr/bin/env bash
# smoke_all.sh – orquesta los smokes. Usa CONTINUE_ON_FAIL=1 para no cortar ante el primer fallo.
set -euo pipefail

CONTINUE_ON_FAIL="${CONTINUE_ON_FAIL:-0}"

run() {
  local name="$1"
  echo "--------------------------------------------------------------------------------"
  echo "▶ Ejecutando ${name}"
  if "./script/${name}"; then
    echo "✓ ${name} OK"
  else
    echo "✗ ${name} FAIL"
    if [[ "${CONTINUE_ON_FAIL}" != "1" ]]; then
      exit 1
    fi
  fi
}

echo "▶ Esperando /v1/health en http://localhost:3000… (máx 120s)"
for i in {1..120}; do
  if curl -sf "http://localhost:3000/v1/health" >/dev/null; then
    echo "✓ API OK"; break
  fi
  sleep 1
  [[ $i -eq 120 ]] && { echo "✗ API no responde"; exit 1; }
done

run smoke_catalogos_mini.sh
run smoke_catalogos.sh
run smoke_tecnico_flujo.sh
run smoke_tecnico.sh
run smoke_cierre_con_linea.sh
run smoke_cierre_idempotente.sh
run smoke_agenda.sh
run smoke_stress_cierre.sh

echo "--------------------------------------------------------------------------------"
echo "✓ Todos los smokes ejecutados."
