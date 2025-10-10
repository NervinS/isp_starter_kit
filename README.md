# ISP FTTH Starter Kit (MVP)

Repo base con:
- `backend/` – API NestJS
- `backend/docker-compose.yml` – Postgres + MinIO + API
- `backend/script/` – bootstrap idempotente y smokes
- `migrations/` – SQL inicial (opcional)
- `pdf_templates/` – plantillas HTML/PDF
- `.github/workflows/ci.yml` – CI base

> **Estado Inventario**: estable con **vista `kardex`**, **regla de inserción** (INSERT en vista → tabla `movimientos`), **trigger** que sincroniza `inventario_tecnico_stock`, **índices** y **traslados entre almacenes** (`fn_mov_traslado` retorna `uuid`). Incluye **smokes** con *fallback* seguro.

---

## Requisitos
- Docker / Docker Compose
- Node 20.x (para correr el backend fuera de Docker)
- `psql` (opcional para ejecutar SQL manual)

---

## Variables de entorno
Copia `.env.example` a `.env` y ajusta según tu entorno.  
Si ejecutas **dentro de Docker**: `DATABASE_URL=postgres://ispuser:isppass@db:5432/ispdb`  
Si ejecutas **API fuera de Docker**: usa el puerto expuesto **5433**:
```env
DATABASE_URL=postgres://ispuser:isppass@127.0.0.1:5433/ispdb

## Troubleshooting

### 1) GitHub Actions / `gh` CLI
- **Mensajes**: `Command 'gh' not found`
- **Causa**: No está instalado el GitHub CLI.
- **Fix (opción A)**:
  ```bash
  sudo apt-get update && sudo apt-get install -y gh
  gh auth login
  gh workflow list
  gh workflow run ci.yml
  gh run list

## Endpoints nuevos / ajustados

- `GET /v1/equipos/disponibles?tipo=ONU|REPETIDOR|ONT`
- `POST /v1/equipos/entregar` — idempotente
- `POST /v1/equipos/devolver` — idempotente
- `GET /v1/equipos/stock?almacen=ALM-PRINC|CENTRAL` o `?tecnico=TEC-6`
- `GET /v1/materiales/disponibles?almacen=CENTRAL` → **307** a `/v1/inventario/stock/almacen/CENTRAL`
- `GET /v1/inventario/kardex/material?...` → **307** a `/v1/inventario/kardex?...`

## Smokes rápidos
```bash
ONLY="smoke_equipos_ciclo.sh,smoke_materiales_ciclo.sh,smoke_kardex_material.sh" ./script/smoke_all.sh

### Qué incluye
- Nuevas rutas:
  - POST `/v1/equipos/reservar`  → `{ ok, _idempotent, equipo: {...} }`
  - POST `/v1/equipos/liberar`   → `{ ok, _idempotent, equipo: {...} }`
  - GET  `/v1/equipos/reservas?tecnicoId=...` → `equipo[]`
- Contrato estabilizado: `equipo` es **objeto** en reservar/liberar (no array).
- `main.ts`: prefijo `/v1` + rewrite de rutas legacy.
- Smokes: inventory ajustado a 409 en insuficiencia.
- Swagger lock actualizado.

### Notas de idempotencia
- Reservar con la misma marca del técnico → `_idempotent: true`.
- Liberar sin marcas → `_idempotent: true`.

### Cómo probar
```bash
docker compose up -d --build api
./backend/script/smoke_all.sh
