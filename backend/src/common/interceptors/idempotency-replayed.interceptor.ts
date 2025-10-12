// src/common/interceptors/idempotency-replayed.interceptor.ts
import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

@Injectable()
export class IdempotencyReplayedInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      tap((data) => {
        // Solo aplica a HTTP
        const http = context.switchToHttp();
        const res: any = http.getResponse();

        const isReplay =
          data && (data._idempotent === true || data._idempotent === 'true');

        if (isReplay) {
          // Express: setHeader ; Fastify: header
          if (typeof res.setHeader === 'function') {
            res.setHeader('Idempotency-Replayed', 'true');
          } else if (typeof res.header === 'function') {
            res.header('Idempotency-Replayed', 'true');
          }
        }
      }),
    );
  }
}
