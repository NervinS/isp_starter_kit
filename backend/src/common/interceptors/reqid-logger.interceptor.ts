// src/common/interceptors/reqid-logger.interceptor.ts
import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { randomUUID } from 'crypto';

@Injectable()
export class ReqIdLoggerInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const http = context.switchToHttp();
    const req = http.getRequest<Request & { requestId?: string }>();
    const res = http.getResponse();

    const rid =
      (req?.headers?.['x-request-id'] as string) ||
      (req as any).requestId ||
      randomUUID();

    // Propaga el header de request-id si no está
    try {
      if (res && typeof res.setHeader === 'function') {
        res.setHeader('X-Request-Id', rid);
      }
    } catch {
      // no-op
    }

    const method = (req as any)?.method || 'GET';
    const url = (req as any)?.url || '';
    const start = Date.now();

    // Log de entrada
    // eslint-disable-next-line no-console
    console.log(`[REQ] ${method} ${url} rid=${rid}`);

    return next.handle().pipe(
      tap({
        next: () => {
          const ms = Date.now() - start;
          const status = (res as any)?.statusCode ?? 200;
          // eslint-disable-next-line no-console
          console.log(`[RES] ${method} ${url} -> ${status} ${ms}ms rid=${rid}`);
        },
        error: (err) => {
          const ms = Date.now() - start;
          const status =
            (res as any)?.statusCode ??
            (err?.status ?? err?.statusCode ?? 500);
          // eslint-disable-next-line no-console
          console.error(
            `[ERR] ${method} ${url} -> ${status} ${ms}ms rid=${rid} msg=${
              err?.message || err
            }`,
          );
        },
      }),
    );
  }
}
