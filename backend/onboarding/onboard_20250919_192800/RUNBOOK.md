# RUNBOOK — ISP Starter Kit (Backend)
> Paquete de onboarding para ingeniería. Este documento se genera automáticamente por `script/onboarding_bundle.sh`.

## 1. Arquitectura (alto nivel)
- **API (NestJS)** expone `/v1/*` para catálogos, ventas, agenda/técnicos e inventario.
- **DB (PostgreSQL)** con tablas núcleo: `tecnicos`, `materiales`, `ordenes`, `ordenes_materiales`, `inv_tecnico`, `ventas`, `orden_cierres_idem`.
- **MinIO** para evidencias (cedula/recibo/firma) y PDFs (recibo/contrato).
- **Front** (Next.js) consume API vía proxy `/api/*`.

## 2. Levantar entorno local
```bash
docker compose up -d           # api, db, (minio si aplica)
docker compose ps
curl -s http://localhost:3000/v1/health
