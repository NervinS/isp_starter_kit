# =========================
# 01) Repo & árbol + snapshot de código + concat TS
# =========================
log "Repo & árbol + snapshot de código + concat TS"

SNAPSHOT_DIR="$OUT_DIR/repo_snapshot"
SNAPSHOT_METHOD="${SNAPSHOT_METHOD:-tar}"     # tar | rsync | cp
SNAPSHOT_TIMEOUT_SEC="${SNAPSHOT_TIMEOUT_SEC:-120}"
SKIP_SNAPSHOT="${SKIP_SNAPSHOT:-0}"

# Árbol / git info
{
  echo "# git remotes"; git remote -v || true; echo
  echo "# git status";  git status -s || true; echo
  echo "# últimas 50 commits"; git log --oneline -n 50 || true; echo
  echo "# ramas locales"; git branch -vv || true; echo
  echo "# tags"; git tag -l || true; echo
  echo "# árbol (hasta 4 niveles, sin .git ni node_modules ni dist/out/.next)"
  if command -v tree >/dev/null 2>&1; then
    tree -a -I '.git|node_modules|dist|.next|out|logs' -L 4
  else
    find . -maxdepth 4 \
      -not -path './.git/*' \
      -not -path './node_modules/*' \
      -not -path './dist/*' \
      -not -path './.next/*' \
      -not -path './out/*' \
      -not -path './logs/*'
  fi
} > "$OUT_DIR/01_repo.txt" 2>&1

if [[ "$SKIP_SNAPSHOT" == "1" ]]; then
  echo "== Saltando snapshot de código (SKIP_SNAPSHOT=1) ==" | tee -a "$OUT_DIR/00_index.txt"
else
  echo "== Creando snapshot de código del repo ==" | tee -a "$OUT_DIR/00_index.txt"
  rm -rf "$SNAPSHOT_DIR" && mkdir -p "$SNAPSHOT_DIR"

  try_tar() {
    # Snapshot con tar (más estable que rsync en contenedores)
    # Nota: excluye artefactos pesados y el propio OUT_DIR
    local excludes=(
      --exclude='.git'
      --exclude='node_modules'
      --exclude='dist'
      --exclude='.next'
      --exclude='out'
      --exclude='logs'
      --exclude="$OUT_DIR"
      --exclude="$SNAPSHOT_DIR"
    )
    tar -cf - "${excludes[@]}" . | ( cd "$SNAPSHOT_DIR" && tar -xf - )
  }

  try_rsync() {
    rsync -a --delete \
      --exclude '.git' \
      --exclude 'node_modules' \
      --exclude 'dist' \
      --exclude '.next' \
      --exclude 'out' \
      --exclude 'logs' \
      --exclude "$OUT_DIR" \
      --exclude "$SNAPSHOT_DIR" \
      ./ "$SNAPSHOT_DIR"/
  }

  try_cp() {
    # copia de mejor esfuerzo (puede arrastrar permisos básicos)
    # respetando exclusiones con find | cpio (evita “Argument list too long”)
    ( cd . \
      && find . \
        -path './.git' -prune -o \
        -path './node_modules' -prune -o \
        -path './dist' -prune -o \
        -path './.next' -prune -o \
        -path './out' -prune -o \
        -path './logs' -prune -o \
        -path "./$OUT_DIR" -prune -o \
        -path "./${SNAPSHOT_DIR#./}" -prune -o \
        -type f -print \
      | cpio -pdm "$SNAPSHOT_DIR" )
  }

  run_with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
      timeout "$secs" "$@"
    else
      "$@"
    fi
  }

  ok=0
  method="${SNAPSHOT_METHOD}"
  for candidate in "$method" tar rsync cp; do
    [[ "$candidate" == "tar"   ]] && run_with_timeout "$SNAPSHOT_TIMEOUT_SEC" try_tar   && ok=1 && break
    [[ "$candidate" == "rsync" ]] && run_with_timeout "$SNAPSHOT_TIMEOUT_SEC" try_rsync && ok=1 && break
    [[ "$candidate" == "cp"    ]] && run_with_timeout "$SNAPSHOT_TIMEOUT_SEC" try_cp    && ok=1 && break
  done

  if [[ "$ok" != "1" ]]; then
    echo "WARN: no fue posible crear snapshot con tar/rsync/cp (se continúa sin snapshot)." | tee -a "$OUT_DIR/00_index.txt"
    rm -rf "$SNAPSHOT_DIR"
  fi
fi

# Concatena TODOS los .ts del repo (para “panorámica” rápida)
echo "== Concatenando TODOS los .ts ==" | tee -a "$OUT_DIR/00_index.txt"
ALL_TS="$OUT_DIR/ALL_TS_CONCAT.ts"
rm -f "$ALL_TS"
# Incluye src/ y cualquier .ts fuera de src/, excluye d.ts de node y dist
find . \
  -type f -name '*.ts' \
  -not -path './node_modules/*' \
  -not -path './dist/*' \
  -not -path './.git/*' \
  -print0 \
| sort -z \
| xargs -0 -I{} sh -c 'echo "// ===== FILE: {} ====="; cat "{}"; echo; echo' >> "$ALL_TS"
