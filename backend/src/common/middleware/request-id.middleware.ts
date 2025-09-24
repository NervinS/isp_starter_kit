// src/common/middleware/request-id.middleware.ts
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'crypto';

// Evita depender de "express-serve-static-core"
declare global {
  namespace Express {
    interface Request {
      requestId?: string;
    }
  }
}

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const hdr1 = req.header('x-request-id');
    const hdr2 = req.header('x-correlation-id');
    const rid = (hdr1 && hdr1.trim()) || (hdr2 && hdr2.trim()) || randomUUID();

    // Asignamos y propagamos
    (req as any).requestId = rid;
    res.setHeader('X-Request-Id', rid);

    next();
  }
}
