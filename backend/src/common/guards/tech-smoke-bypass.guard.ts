// src/common/guards/tech-smoke-bypass.guard.ts
import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

@Injectable()
export class TechSmokeBypassGuard implements CanActivate {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (process.env.SMOKE_BYPASS_TECH_GUARD !== '1') return false;

    const http = context.switchToHttp();
    const req: any = http.getRequest();
    const url = String(req?.originalUrl ?? req?.url ?? '');
    if (!/\/v1\/tecnicos\/[^/]+/i.test(url)) return false;

    const params = req?.params ?? {};
    const tecnicoId =
      params.tecnicoId ?? params.id ?? req?.query?.tecnicoId ?? null;

    req.user = {
      ...(req.user ?? {}),
      sub: (req.user?.sub ?? tecnicoId) || '00000000-0000-0000-0000-000000000000',
      tecnicoId: req.user?.tecnicoId ?? tecnicoId ?? req.user?.sub,
      role: req.user?.role ?? 'tecnico',
      rol: req.user?.rol ?? 'tecnico',
      scope: req.user?.scope ?? ['tecnico'],
      permissions: req.user?.permissions ?? ['tecnico'],
    };
    return true;
  }
}
