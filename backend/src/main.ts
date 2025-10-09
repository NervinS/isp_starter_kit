// src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { RequestMethod } from '@nestjs/common';
import type { Request, Response, NextFunction } from 'express';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Prefijo global /v1; dejamos GET /health sin prefijo para sondas/smokes
  app.setGlobalPrefix('v1', {
    exclude: [{ path: 'health', method: RequestMethod.GET }],
  });

  // *** Compatibilidad sin /v1: REWRITE (no redirige) ***
  const noV1 = /^\/(inventario|materiales|tecnicos|ordenes|agenda|pdf|jobs|metrics)(\/|$)/;
  (app as any).use((req: Request, _res: Response, next: NextFunction) => {
    if (!req.originalUrl.startsWith('/v1/') && noV1.test(req.originalUrl)) {
      const rewritten = '/v1' + req.url;
      // reescribe para router interno de Nest/Express
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

  const port = Number(process.env.PORT || 3000);
  const host = String(process.env.HOST || '0.0.0.0');
  await app.listen(port, host);
  console.log(`API listening on http://${host}:${port}`);
}
bootstrap();
