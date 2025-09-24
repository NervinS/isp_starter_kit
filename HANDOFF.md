# Handoff – ISP Starter Kit

## Resumen
- Backend NestJS y Frontend Next.js funcionando.
- MinIO en NAT (puerto 9000) — URLs firmadas deben usar el host público.
- Pendientes: guardado de evidencias (recibo/cedula/firma) desde Front; estampado de firma en contrato; mostrar enlaces en UI al pagar.

## Cómo levantar
Backend:
  cp backend/.env.example backend/.env   # ajustar credenciales
  cd backend && npm i && npm run start:dev
Frontend:
  cp frontend/.env.local.example frontend/.env.local
  cd frontend && npm i && npm run dev

DB:
  psql -U ispuser -h localhost -d ispdb < db/backup.sql

## Red/NAT
- IP pública: 38.188.225.6
- MinIO externo: http://38.188.225.6:9000  (ajustar MINIO_EXTERNAL_URL)
- Backend: http://127.0.0.1:3000/v1
- Frontend: http://127.0.0.1:3001

## Variables clave
- MINIO_ENDPOINT/MINIO_EXTERNAL_URL, MINIO_ACCESS_KEY, MINIO_SECRET_KEY
- API_BASE_SSR (front), NEXT_PUBLIC_API_BASE=/api

## Endpoints usados
- Auth: POST /v1/auth/login
- Planes: GET /v1/planes
- Ventas:
  - POST /v1/ventas
  - POST /v1/ventas/:codigo/evidencias  (FormData: recibo, cedula, firma)
  - POST /v1/ventas/:codigo/pagar  (retorna recibo_url y contrato_url)

## Repro de issues
1) Crear venta desde /ventas.
2) Subir recibo/cedula y firma (canvas).
3) Pagar -> debería:
   - Guardar evidencias en MinIO (evidencias/ventas/VEN-XXXX/…)
   - Estampar firma en contrato.pdf
   - Devolver URLs firmadas (recibo_url, contrato_url) para la UI.

