#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
echo "=== 🚦 Smoke full (mínimo) ==="
set -x
"$here/smoke_kardex_min.sh"
"$here/smoke_inventario_min.sh"
"$here/smoke_tecnicos_min.sh"
"$here/smoke_pdf.sh"
"$here/smoke_jobs.sh"
"$here/smoke_metrics.sh"
"$here/smoke_ordenes.sh"
"$here/smoke_agenda.sh"
"$here/smoke_agenda_verbose.sh"
"$here/smoke_inventario_traslado.sh"
"$here/smoke_inventory.sh"
"$here/smoke_ins_equipos_cierre.sh"
set +x
echo "[ OK ] Todos los smokes mínimos OK."
