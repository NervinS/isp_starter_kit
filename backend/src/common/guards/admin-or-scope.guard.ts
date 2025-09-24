// src/common/guards/admin-or-scope.guard.ts
import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

/**
 * AdminOrScopeGuard con bypass para smoke tests.
 * - Si SMOKE_BYPASS_TECH_GUARD=1 y la ruta es /v1/tecnicos/:id/..., permite siempre.
 * - Fuera de bypass, aplica una validación mínima: admin o scope/permiso 'tecnico'.
 *
 * Esta versión es segura para smoke tests y no afecta endpoints no-tecnico.
 */
@Injectable()
export class AdminOrScopeGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const bypass = process.env.SMOKE_BYPASS_TECH_GUARD === '1';
    const req: any = context.switchToHttp().getRequest();
    const url = String(req?.originalUrl ?? req?.url ?? '');
    const isTecnicosRoute = /\/v1\/tecnicos\/[^/]+/i.test(url);

    if (bypass && isTecnicosRoute) return true;

    const user = req?.user ?? {};
    const isAdmin =
      user.role === 'admin' ||
      user.rol === 'admin' ||
      (Array.isArray(user.roles) && user.roles.includes('admin')) ||
      (Array.isArray(user.authorities) && user.authorities.includes('admin')) ||
      user.perfil === 'admin';

    const hasTecnicoScope =
      user.scope === 'tecnico' ||
      (Array.isArray(user.scope) && user.scope.includes('tecnico')) ||
      (Array.isArray(user.scopes) && user.scopes.includes('tecnico')) ||
      (Array.isArray(user.permissions) && user.permissions.includes('tecnico')) ||
      (Array.isArray(user.permisos) && user.permisos.includes('tecnico')) ||
      user.permission === 'tecnico';

    return !!(isAdmin || hasTecnicoScope);
  }
}

