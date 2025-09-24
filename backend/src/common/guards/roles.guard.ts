// src/common/guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) return true;

    const request = context.switchToHttp().getRequest();
    const user = request.user || {};

    // Normaliza posibles fuentes: role:string y roles:string[]
    const roleStr = typeof user.role === 'string' ? user.role.toLowerCase() : '';
    const rolesArr: string[] = Array.isArray(user.roles)
      ? (user.roles as string[]).map((r) => (typeof r === 'string' ? r.toLowerCase() : ''))
      : [];

    const userRoles = new Set([roleStr, ...rolesArr].filter(Boolean));
    return required.some((r) => userRoles.has(r.toLowerCase()));
  }
}
