#!/usr/bin/env bash
# smoke_all.sh — orquestador de todos los smokes
# Uso:
#   ./script/smoke_all.sh
#   CONTINUE_ON_FAIL=1 ./script/smoke_all.sh     # sigue aunque fallen
#   ONLY="smoke_kardex_min.sh,smoke_metrics.sh" ./script/smoke_all.sh   # subset
#   SKIP="smoke_jobs.sh,smoke_pdf.sh" ./script/smoke_all.sh             # salta algunos
#
# Variables:
#   CONTINUE_ON_FAIL=1   -> no aborta en el primer fallo (default: 0)
#   ONLY="a,b,c"         -> solo corre estos (nombres de archivos, coma separados)
#   SKIP="a,b,c"         -> salta estos (coma separados)
#   LOG_DIR              -> directorio de logs (default: logs/smoke_all.<timestamp>)
#   VERBOSE=1            -> eco de comandos (set -x)

set -euo pipefail

[[ "${VERBOSE:-0}" == "1" ]] && set -x

# --- Config ---
ts="$(date +%Y%m%d-%H%M%S)"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/script"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/logs/smoke_all.${ts}}"
mkdir -p "${LOG_DIR}"

# Falla rápido por defecto; se puede desactivar
CONTINUE_ON_FAIL="${CONTINUE_ON_FAIL:-0}"
# --- ENV para agenda (idempotente) ---
API="${API:-http://localhost:3000/v1}"
export API
if [[ -z "${REAGENDA_URL_TEMPLATE:-}" ]]; then
  export REAGENDA_URL_TEMPLATE="$API/agenda/ordenes/%s/reagendar"
fi


# Lista base (en el orden que pediste)
ALL_SCRIPTS=(
  # nuevos f1
  "smoke_materiales_disponibles.sh"
  "smoke_equipos_disponibles.sh"
  "smoke_equipos_asignar.sh"
  "smoke_equipos_devolver.sh"
  "smoke_equipos_stock.sh"
  "smoke_equipos_ciclo.sh"
  "smoke_equipos_historial.sh"
  "smoke_materiales_ciclo.sh"
  "smoke_inventario_idem.sh"
  "smoke_inventario_min.sh"
  "smoke_kardex_min.sh"
  "smoke_kardex_material.sh"
  "smoke_tecnicos_min.sh"
  "smoke_ordenes.sh"
  "smoke_agenda.sh"
  "smoke_agenda_verbose.sh"
  "smoke_inventario_traslado.sh"
  "smoke_inventory.sh"
  "run_smokes_and_logs.sh"
  "smoke_ins_equipos_cierre.sh"
  "smoke_pdf.sh"
  "smoke_jobs.sh"
  "smoke_metrics.sh"
  "smoke_ventas_ins.sh"
)

# Filtrado opcional via ONLY / SKIP
IFS=',' read -r -a ONLY_ARR <<< "${ONLY:-}"
IFS=',' read -r -a SKIP_ARR <<< "${SKIP:-}"

in_array() {
  local needle="$1"; shift
  local x
  for x in "$@"; do
    [[ -n "$x" && "$x" == "$needle" ]] && return 0
  done
  return 1
}

should_run() {
  local name="$1"
  if [[ ${#ONLY_ARR[@]} -gt 0 ]]; then
    in_array "$name" "${ONLY_ARR[@]}" || return 1
  fi
  if [[ ${#SKIP_ARR[@]} -gt 0 ]]; then
    in_array "$name" "${SKIP_ARR[@]}" && return 1
  fi
  return 0
}

# --- Helpers de salida bonita ---
b() { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }

# --- Verificaciones mínimas ---
if [[ ! -d "${SCRIPT_DIR}" ]]; then
  red "No existe ${SCRIPT_DIR}. ¿Estás en backend/?"
  exit 2
fi

# --- Run ---
declare -a SUM_NAMES=()
declare -a SUM_RESULTS=()
declare -a SUM_DURATIONS=()
declare -a SUM_LOGS=()

b "=== 🚦 smoke_all — inicio ${ts} ==="
echo "Logs en: ${LOG_DIR}"
echo

overall_status=0

for s in "${ALL_SCRIPTS[@]}"; do
  if ! should_run "$s"; then
    yellow "↷ Skip ${s}"
    continue
  fi

  path="${SCRIPT_DIR}/${s}"
  if [[ ! -x "$path" ]]; then
    if [[ -f "$path" ]]; then
      yellow "🔧 ${s} no es ejecutable, intentando chmod +x"
      chmod +x "$path" || true
    fi
  fi
  if [[ ! -x "$path" ]]; then
    red "✗ No se puede ejecutar ${s} (no existe o no es ejecutable)"
    if [[ "$CONTINUE_ON_FAIL" == "1" ]]; then
      SUM_NAMES+=("$s"); SUM_RESULTS+=("NOEXEC"); SUM_DURATIONS+=("-"); SUM_LOGS+=("-")
      overall_status=1
      continue
    else
      exit 3
    fi
  fi

  b "────────────────────────────────────────────────────────"
  b "▶ ${s}"
  log_file="${LOG_DIR}/${s%.sh}.${ts}.log"

  start_ns=$(date +%s%N)
  set +e
  "${path}" | tee "${log_file}"
  code=${PIPESTATUS[0]}
  set -e
  end_ns=$(date +%s%N)
  dur_ms=$(( (end_ns - start_ns)/1000000 ))

  if [[ $code -eq 0 ]]; then
    green "✓ ${s} OK (${dur_ms} ms)"
    result="OK"
  else
    red "✗ ${s} FAIL (exit=${code}, ${dur_ms} ms) → log: ${log_file}"
    result="FAIL"
    overall_status=1
    if [[ "$CONTINUE_ON_FAIL" != "1" ]]; then
      echo
      red "⛔ Abortado por FAIL (export CONTINUE_ON_FAIL=1 para continuar)."
      # Resumen parcial
      SUM_NAMES+=("$s"); SUM_RESULTS+=("$result"); SUM_DURATIONS+=("${dur_ms} ms"); SUM_LOGS+=("${log_file}")
      break
    fi
  fi

  SUM_NAMES+=("$s")
  SUM_RESULTS+=("$result")
  SUM_DURATIONS+=("${dur_ms} ms")
  SUM_LOGS+=("${log_file}")
  echo
done

echo
b "=== 📊 Resumen smoke_all ==="
printf "%-32s | %-6s | %-10s | %s\n" "Script" "Res" "Duración" "Log"
printf -- "----------------------------------+--------+------------+---------------------------------------------\n"
for i in "${!SUM_NAMES[@]}"; do
  name="${SUM_NAMES[$i]}"
  res="${SUM_RESULTS[$i]}"
  dur="${SUM_DURATIONS[$i]}"
  log="${SUM_LOGS[$i]}"
  printf "%-32s | %-6s | %-10s | %s\n" "$name" "$res" "$dur" "$log"
done
echo
if [[ $overall_status -eq 0 ]]; then
  green "🎉 Todos los smokes OK"
else
  red "⚠️  Hubo fallos. Revisa los logs en: ${LOG_DIR}"
fi

exit $overall_status
