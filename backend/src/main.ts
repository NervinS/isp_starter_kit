import "reflect-metadata";
// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { RequestMethod, ValidationPipe } from '@nestjs/common';
import type { Request, Response, NextFunction } from 'express';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { cors: true });

  // Prefijo global /v1; dejamos GET /health sin prefijo para sondas/smokes
  app.setGlobalPrefix('v1', {
    exclude: [{ path: 'health', method: RequestMethod.GET }],
  });

  // Validación global de DTOs (contratos robustos)
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,                 // elimina campos extra
      forbidNonWhitelisted: true,      // 400 si envían campos no permitidos
      transform: true,                 // convierte tipos (body/query/params)
      transformOptions: { enableImplicitConversion: true }, // ej: string->number
    }),
  );

  // --- Compatibilidad sin /v1: REWRITE (no redirige) ---
  // Añadimos 'equipos' a la lista de rutas legacy sin prefijo
  const noV1 = /^\/(inventario|materiales|tecnicos|ordenes|agenda|pdf|jobs|metrics|equipos)(\/|$)/;
  (app as any).use((req: Request, _res: Response, next: NextFunction) => {
    if (!req.originalUrl.startsWith('/v1/') && noV1.test(req.originalUrl)) {
      const rewritten = '/v1' + req.url;
      // Reescribe para el router interno de Nest/Express
      (req as any).url = rewritten;
      (req as any).originalUrl = rewritten;
    }
    next();
  });

  // Healthcheck simple SIN prefijo (/health)
  const http = app.getHttpAdapter().getInstance();
  http.get('/health', (_req: Request, res: Response) => {
    res.status(200).json({ ok: true });
  });

  // --- Swagger (dev only) ---
  if (process.env.DOCS_ENABLED === '1') {
    const swagger = await import('@nestjs/swagger');
    const config = new swagger.DocumentBuilder()
      .setTitle('ISP Backend API')
      .setVersion('1.0')
      .addBearerAuth()
      .addApiKey({ type: 'apiKey', name: 'x-api-key', in: 'header' }, 'x-api-key')
      .build();
    const document = swagger.SwaggerModule.createDocument(app, config);
    // UI en /v1/docs y JSON en /v1/docs-json
    swagger.SwaggerModule.setup('/v1/docs', app, document);
    http.get('/v1/docs-json', (_req: Request, res: Response) => res.json(document));
    // Nota: si tienes guard de api-key, asegúrate que /v1/docs-json esté en whitelist
  }

  const port = Number(process.env.PORT || 3000);
  const host = String(process.env.HOST || '0.0.0.0');
  await app.listen(port, host);
  // eslint-disable-next-line no-console
  console.log(`API listening on http://${host}:${port}`);
}
bootstrap();
