// src/common/guards/api-key.guard.ts
import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  private readonly headerName = 'x-api-key';

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    const expected = (process.env.API_KEY ?? '').trim();

    // 1) Si no configuras API_KEY, no bloquea nada (no rompe E2E ni dev)
    if (!expected) return true;

    const path: string = req.path || req.url || '';
    const method: string = (req.method || '').toUpperCase();

    // 2) Rutas públicas (observabilidad y docs)
    //    - Health
    //    - Swagger (UI y JSON)
    //    - Archivos estáticos de Swagger
    if (
      path === '/v1/health' ||
      path === '/v1/healthz' ||
      path === '/v1/docs' ||
      path === '/v1/docs-json' ||
      path.startsWith('/v1/docs/')
    ) {
      return true;
    }

    // 3) Acepta API key por header y también por query ?api_key=
    const headerKey = (req.headers?.[this.headerName] as string | undefined)?.trim();
    const queryKey =
      typeof req.query?.api_key === 'string' ? (req.query.api_key as string).trim() : undefined;

    if (headerKey === expected || queryKey === expected) {
      return true;
    }

    // 4) Rechaza
    throw new UnauthorizedException(
      `API key inválida. Usa header "${this.headerName}" o query "api_key".`,
    );
  }
}
