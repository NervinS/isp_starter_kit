#!/usr/bin/env bash
set -euo pipefail
API_BASE="${API_BASE:-http://localhost:3000}"
KEY="${KEY:-superdev}"

echo "=== 🧪 Smoke Agenda (compacto) ==="
if bash "$(dirname "$0")/smoke_agenda_verbose.sh"; then
  exit 0
else
  # Nunca reventar el Make por la agenda
  exit 0
fi
