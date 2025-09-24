# ISP FTTH Starter Kit (MVP)
Este paquete contiene:
- `docker-compose.yml` para Postgres, Redis, RabbitMQ y MinIO.
- `backend/` esqueleto NestJS.
- `frontend/` esqueleto Next.js.
- `migrations/` SQL inicial.
- `pdf_templates/` plantillas HTML (Contrato, Factura, Ticket pago).
- `.env.example` variables de entorno.

## Pasos rápidos
1) Copia `.env.example` a `.env` y ajusta valores.
2) `docker compose up -d` (primera vez tarda unos minutos).
3) Ejecuta migraciones en Postgres: `psql $POSTGRES_URL -f migrations/00_all.sql`
4) Levanta backend: `cd backend && npm i && npm run start:dev`
5) Levanta frontend: `cd frontend && npm i && npm run dev`

## Orden recomendado de implementación
- Ventas → Órdenes → SmartOLT
- Facturación y Notificaciones
- RBAC, Observabilidad, Reportes, Hardening
