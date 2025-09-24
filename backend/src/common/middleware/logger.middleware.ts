// src/common/middleware/logger.middleware.ts
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const startedAt = process.hrtime.bigint();
    const rid = (req as any).requestId ?? '-';
    const isHealth = req.url?.startsWith('/v1/health');

    if (!isHealth) {
      // eslint-disable-next-line no-console
      console.log(`[REQ] ${req.method} ${req.originalUrl || req.url} rid=${rid}`);
    }

    res.on('finish', () => {
      if (!isHealth) {
        const endedAt = process.hrtime.bigint();
        const ms = Number(endedAt - startedAt) / 1e6;
        // eslint-disable-next-line no-console
        console.log(
          `[RES] ${req.method} ${req.originalUrl || req.url} -> ${res.statusCode} ${ms.toFixed(1)}ms rid=${rid}`,
        );
      }
    });

    next();
  }
}
