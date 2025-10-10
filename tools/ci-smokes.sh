#!/usr/bin/env bash
set -euo pipefail

BRANCH="${BRANCH:-feat/f1-equipos-controller}"
WORKFLOW_NAME="Backend Smokes"

# Auth no interactiva si hay GH_TOKEN
if ! gh auth status >/dev/null 2>&1; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "🔐 Autenticando gh con GH_TOKEN…"
    gh auth login --with-token <<<"$GH_TOKEN" >/dev/null
  else
    echo "⚠️ gh no autenticado y GH_TOKEN no está seteado."
    echo "   export GH_TOKEN='xxxxxxxx' y re-ejecuta; o corre 'gh auth login'."
    exit 1
  fi
fi

echo "🌿 Preparando rama ${BRANCH}…"
git fetch origin
git checkout -B "$BRANCH" "origin/$BRANCH" || git checkout -B "$BRANCH"

echo "🚀 Commit vacío para gatillar workflow '${WORKFLOW_NAME}'…"
git commit --allow-empty -m "ci: trigger ${WORKFLOW_NAME}" || true
git push origin "$BRANCH"

echo "⏳ Buscando RUN_ID de '${WORKFLOW_NAME}' para ${BRANCH}…"
RUN_ID=""
for i in {1..30}; do
  RUN_ID=$(gh run list -w "$WORKFLOW_NAME" --limit 40 \
    --json databaseId,headBranch,createdAt \
    -q "[ .[] | select(.headBranch==\"$BRANCH\") ] | sort_by(.createdAt) | reverse | .[0].databaseId" 2>/dev/null || true)
  [[ -n "$RUN_ID" ]] && break
  sleep 3
done
[[ -z "$RUN_ID" ]] && { echo "❌ No encontré runs"; exit 1; }

# Esperar a que termine (no falla si termina con error)
gh run watch "$RUN_ID" || true

# ==== Descargar artifact cuyo nombre empieza por 'smoke-logs' ====
OUT="/tmp/smokes_ci/${RUN_ID}_$(date +%s)"
mkdir -p "$OUT"

ARTIFACT_NAME=$(gh run view "$RUN_ID" --json artifacts -q '.artifacts[].name' | grep '^smoke-logs' | head -n1 || true)
if [[ -z "${ARTIFACT_NAME:-}" ]]; then
  echo "⚠️ No hay artifact 'smoke-logs*' aún. Reintentando hasta 30 veces…"
  for i in {1..30}; do
    ARTIFACT_NAME=$(gh run view "$RUN_ID" --json artifacts -q '.artifacts[].name' | grep '^smoke-logs' | head -n1 || true)
    [[ -n "$ARTIFACT_NAME" ]] && break
    echo "⏳ Artifact aún no listo; reintentando… ($i/30)"
    sleep 5
  done
fi

if [[ -z "${ARTIFACT_NAME:-}" ]]; then
  echo "❌ No se encontró artifact 'smoke-logs*' en el run $RUN_ID."
  # Aún así muestra logs del job para diagnosticar:
  echo "── Logs del job smokes ──"
  gh run view "$RUN_ID" --job smokes --log || true
  exit 1
fi

echo "📥 Bajando artifact '$ARTIFACT_NAME' a: $OUT"
gh run download "$RUN_ID" -n "$ARTIFACT_NAME" -D "$OUT"

echo "── archivos en $OUT ──"
find "$OUT" -maxdepth 2 -type f -printf "%P\n" | sort

# Vistas rápidas
SMOKE_LOG=$(find "$OUT" -type f -name "smoke_equipos_ciclo.*.log" | head -n1 || true)
API_LOG=$(find "$OUT" -type f -name "api.log" | head -n1 || true)
COMPOSE_LOG=$(find "$OUT" -type f -name "compose-logs.txt" | head -n1 || true)

[ -n "${SMOKE_LOG:-}" ]   && { echo "—— smoke_equipos_ciclo ——"; sed -n '1,200p' "$SMOKE_LOG"; } || echo "(no smoke_equipos_ciclo.*.log)"
echo "— api log —"
[ -n "${API_LOG:-}" ]     && sed -n '1,200p' "$API_LOG"     || echo "(no api.log en el artefacto)"
echo "— compose logs —"
[ -n "${COMPOSE_LOG:-}" ] && sed -n '1,200p' "$COMPOSE_LOG" || echo "(no compose-logs.txt en el artefacto)"

echo "✅ Listo."
