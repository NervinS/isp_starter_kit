# ISP FTTH Starter Kit (MVP)

Repo base con:
- `backend/` – API NestJS
- `backend/docker-compose.yml` – Postgres + MinIO + API
- `backend/script/` – bootstrap idempotente y smokes
- `migrations/` – SQL inicial (opcional)
- `pdf_templates/` – plantillas HTML/PDF
- `.github/workflows/ci.yml` – CI base

> **Estado Inventario**: estable con **vista `kardex`**, **regla de inserción** (INSERT en vista → tabla `movimientos`), **trigger** que sincroniza `inventario_tecnico_stock` y **índices**. Incluye **smokes** con *fallback* seguro.

---

## Requisitos
- Docker / Docker Compose
- Node 20.x (para correr el backend fuera de Docker)
- psql (opcional para ejecutar SQL manual)

---

## Variables de entorno
Copia `.env.example` a `.env` y ajusta según tu entorno.  
Si ejecutas **dentro de Docker**, la API usa la red interna y `DATABASE_URL=postgres://ispuser:isppass@db:5432/ispdb`.  
Si ejecutas **la API fuera de Docker**, usa el puerto expuesto **5433**:

```env
DATABASE_URL=postgres://ispuser:isppass@127.0.0.1:5433/ispdb
