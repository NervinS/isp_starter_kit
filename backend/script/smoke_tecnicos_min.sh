#!/usr/bin/env bash
set -euo pipefail

TITLE="=== 🛠️  Smoke Técnicos (mínimo) v12 ==="

# --- Config overridable por env ---
API_BASE="${API_BASE:-http://localhost:3000}"        # sin /v1
TECH_ID="${TECH_ID:-1}"
MATERIAL_ID="${MATERIAL_ID:-3}"
TURNO="${TURNO:-AM}"

# Se llenará dinámicamente
PSQL="${PSQL:-}"

fail() { echo -e "\n❌ $*" >&2; exit 1; }

detect_health_and_set_base_v1() {
  local base="${API_BASE%/}"
  local candidates=("$base/v1/health" "$base/health")
  echo "⏳ Esperando API (probando /v1/health y /health sobre $base) ..."
  for url in "${candidates[@]}"; do
    for i in {1..60}; do
      if curl -sf --max-time 2 "$url" >/dev/null; then
        echo "✅ API OK en $url"
        API_V1="${base}/v1"
        export API_V1
        return 0
      fi
      printf "\r  intento %02d/60 ..." "$i"
      sleep 2
    done
  done
  echo
  echo "🧪 Diagnóstico rápido:"
  for url in "${candidates[@]}"; do
    echo "  - $url"
    curl -s -o /dev/null -w "    -> http_code=%{http_code} time_total=%{time_total}s\n" "$url" || true
  done
  echo "  - docker compose ps"
  docker compose ps || true
  echo "  - logs api (últimas 50 líneas)"
  docker compose logs --tail=50 api || true
  return 1
}

get_pg_password() {
  # 1) Si ya viene del entorno, úsalo
  if [[ -n "${PGPASSWORD:-}" ]]; then
    echo "🔑 Usando contraseña Postgres desde \$PGPASSWORD del entorno."
    return 0
  fi
  # 2) Intentar leerla desde el contenedor db (POSTGRES_PASSWORD)
  local pw=""
  pw="$(docker compose exec -T db printenv POSTGRES_PASSWORD 2>/dev/null || true)"
  if [[ -n "$pw" ]]; then
    export PGPASSWORD="$pw"
    echo "🔑 Obtuve password desde el contenedor db (POSTGRES_PASSWORD)."
    return 0
  fi
  # 3) Pedirla al usuario una sola vez
  read -rsp "🔑 Contraseña Postgres para usuario ispuser: " pw
  echo
  if [[ -z "$pw" ]]; then
    return 1
  fi
  export PGPASSWORD="$pw"
  return 0
}

detect_psql() {
  # Con PGPASSWORD ya exportado
  local try1="psql -h 127.0.0.1 -p 5433 -U ispuser -d ispdb -v ON_ERROR_STOP=1"
  local try2="psql -h db         -p 5432 -U ispuser -d ispdb -v ON_ERROR_STOP=1"

  echo "⏳ Probando conexión a Postgres..."
  if echo "select 1;" | ${try1} >/dev/null 2>&1; then
    PSQL="${try1}"
    echo "✅ Postgres OK via 127.0.0.1:5433"
    return 0
  else
    echo "  ↪️ No respondió 127.0.0.1:5433; probando db:5432…"
  fi
  if echo "select 1;" | ${try2} >/dev/null 2>&1; then
    PSQL="${try2}"
    echo "✅ Postgres OK via db:5432"
    return 0
  fi

  echo "🧪 Diagnóstico Postgres:"
  echo "  - docker compose ps"
  docker compose ps || true
  echo "  - logs db (últimas 50 líneas)"
  docker compose logs --tail=50 db || true
  return 1
}

echo "$TITLE"

# 1) API viva
detect_health_and_set_base_v1 || fail "API no disponible en ${API_BASE}"

# 2) Obtener password y probar Postgres
get_pg_password || fail "No tengo contraseña para Postgres (ispuser)."
detect_psql || fail "No pude conectar a Postgres ni por 127.0.0.1:5433 ni por db:5432"

echo "🔧 Bootstrap BD (idempotente + compat cierre)..."
$PSQL <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.tecnicos (
  id SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL DEFAULT 'Técnico Demo'
);
INSERT INTO public.tecnicos (id, nombre)
SELECT 1, 'Técnico 1' WHERE NOT EXISTS (SELECT 1 FROM public.tecnicos WHERE id=1);

CREATE TABLE IF NOT EXISTS public.materiales (
  id SERIAL PRIMARY KEY,
  codigo TEXT UNIQUE,
  nombre TEXT NOT NULL
);
INSERT INTO public.materiales (id, codigo, nombre)
SELECT 3, 'MAT-003', 'Material 3'
WHERE NOT EXISTS (SELECT 1 FROM public.materiales WHERE id=3);

CREATE TABLE IF NOT EXISTS public.inventario_tecnico_stock (
  tecnico_id INT NOT NULL,
  material_id INT NOT NULL,
  cantidad INT NOT NULL DEFAULT 0,
  PRIMARY KEY (tecnico_id, material_id)
);
INSERT INTO public.inventario_tecnico_stock (tecnico_id, material_id, cantidad)
SELECT 1, 3, 1
WHERE NOT EXISTS (
  SELECT 1 FROM public.inventario_tecnico_stock WHERE tecnico_id=1 AND material_id=3
);

CREATE TABLE IF NOT EXISTS public.movimientos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo TEXT NOT NULL,
  material_id INT NOT NULL,
  cantidad INT NOT NULL,
  tecnico_id INT,
  motivo TEXT,
  created_at timestamptz NOT NULL DEFAULT now(),
  almacen_origen_id INT,
  almacen_destino_id INT
);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='movimientos' AND column_name='motivo') THEN
    EXECUTE 'ALTER TABLE public.movimientos ADD COLUMN motivo TEXT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='movimientos' AND column_name='created_at') THEN
    EXECUTE 'ALTER TABLE public.movimientos ADD COLUMN created_at timestamptz NOT NULL DEFAULT now()';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='movimientos' AND column_name='almacen_origen_id') THEN
    EXECUTE 'ALTER TABLE public.movimientos ADD COLUMN almacen_origen_id INT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='movimientos' AND column_name='almacen_destino_id') THEN
    EXECUTE 'ALTER TABLE public.movimientos ADD COLUMN almacen_destino_id INT';
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.ordenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT UNIQUE NOT NULL,
  cliente_nombre TEXT,
  fecha_programada DATE,
  turno TEXT,
  estado TEXT NOT NULL DEFAULT 'agendada',
  tecnico_id INT,
  usuario_id INT,
  iniciada_at timestamptz,
  cerrada_at timestamptz
);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='ordenes' AND indexname='idx_ordenes_codigo') THEN
    EXECUTE 'CREATE INDEX idx_ordenes_codigo ON public.ordenes(codigo)';
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.orden_materiales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL,
  material_id INT NOT NULL,
  cantidad INT NOT NULL DEFAULT 1,
  descontado BOOLEAN NOT NULL DEFAULT FALSE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
DO $$
DECLARE col_type text;
BEGIN
  SELECT data_type INTO col_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='orden_materiales' AND column_name='orden_id';
  IF col_type IS NOT NULL AND col_type <> 'uuid' THEN
    EXECUTE 'ALTER TABLE public.orden_materiales DROP COLUMN orden_id';
    EXECUTE 'ALTER TABLE public.orden_materiales ADD COLUMN orden_id UUID NOT NULL';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='orden_materiales' AND column_name='descontado') THEN
    EXECUTE 'ALTER TABLE public.orden_materiales ADD COLUMN descontado BOOLEAN NOT NULL DEFAULT FALSE';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='orden_materiales' AND column_name='created_at') THEN
    EXECUTE 'ALTER TABLE public.orden_materiales ADD COLUMN created_at timestamptz NOT NULL DEFAULT now()';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='orden_materiales' AND column_name='updated_at') THEN
    EXECUTE 'ALTER TABLE public.orden_materiales ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now()';
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='orden_materiales_set_updated_at') THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION orden_materiales_set_updated_at()
      RETURNS trigger AS $$
      BEGIN
        NEW.updated_at := now();
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    $fn$;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_orden_materiales_set_updated_at') THEN
    EXECUTE 'CREATE TRIGGER trg_orden_materiales_set_updated_at
             BEFORE UPDATE ON public.orden_materiales
             FOR EACH ROW EXECUTE FUNCTION orden_materiales_set_updated_at()';
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS public.orden_evidencias (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_id UUID NOT NULL,
  tipo TEXT NOT NULL,
  url TEXT NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
SQL

STAMP="$(date +%y%m%d%H%M%S)"
CODIGO="MAN-${STAMP}"
HOY="$(date +%F)"

echo "🧾 Creando y ASIGNANDO orden ${CODIGO} (hoy ${HOY}, turno ${TURNO}) por SQL..."
$PSQL <<SQL
INSERT INTO public.ordenes (codigo, cliente_nombre, fecha_programada, turno, estado, tecnico_id, usuario_id)
VALUES ('${CODIGO}', 'Cliente Demo', '${HOY}', '${TURNO}', 'agendada', NULL, 1)
ON CONFLICT (codigo) DO NOTHING;

UPDATE public.ordenes
   SET tecnico_id=${TECH_ID}, estado='asignada'
 WHERE codigo='${CODIGO}';
SQL

echo "🔎 Stock técnico ${TECH_ID} antes:"
curl -s "${API_V1}/inventario/tecnicos/${TECH_ID}/stock" | jq .

echo "▶️  Iniciar orden por código (técnico ${TECH_ID})..."
curl -s -X POST "${API_V1}/tecnicos/${TECH_ID}/ordenes/codigo/${CODIGO}/iniciar" \
  -H 'Content-Type: application/json' -d '{}' | jq .

echo "✅ Cerrar orden con firma/evidencias y 1 material (id=${MATERIAL_ID})..."
CLOSE_PAYLOAD="$(jq -n --arg mid "${MATERIAL_ID}" '{
  materiales: [{ material_id: ($mid|tonumber), cantidad: 1 }],
  evidencias: [
    { tipo: "foto", url: "http://127.0.0.1:9000/evidencias/demo-foto.jpg" },
    { tipo: "firma", url: "http://127.0.0.1:9000/evidencias/demo-firma.png" }
  ]
}')"
curl -s -X POST "${API_V1}/tecnicos/${TECH_ID}/ordenes/codigo/${CODIGO}/cerrar" \
  -H 'Content-Type: application/json' -d "${CLOSE_PAYLOAD}" | jq .

echo "🔎 Stock técnico ${TECH_ID} después:"
curl -s "${API_V1}/inventario/tecnicos/${TECH_ID}/stock" | jq .

echo "📌 Estado final de la orden en BD:"
$PSQL <<SQL
SELECT
  codigo, estado, tecnico_id,
  (iniciada_at IS NOT NULL) AS iniciada,
  (cerrada_at IS NOT NULL)  AS cerrada
FROM public.ordenes
WHERE codigo='${CODIGO}';
SQL

echo
echo "🎉 Smoke Técnicos mínimo ejecutado"
